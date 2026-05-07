class FetchBookwyrmReviewsJob < ApplicationJob
  queue_as :low_priority

  REVIEW_TYPES = %w[Review Article].freeze
  REQUEST_TIMEOUT = 30
  PUBLIC_AUDIENCE = "https://www.w3.org/ns/activitystreams#Public"

  def self.schedule_unless_pending
    already_queued = Delayed::Backend::Mongoid::Job
      .exists?(failed_at: nil, handler: /job_class: FetchBookwyrmReviewsJob\n/)
    perform_later(reschedulable: true) unless already_queued
  end

  def perform(reschedulable: true)
    manual_perform(reschedulable)
  end

  def manual_perform(reschedulable = false, limit: 1000)
    bookwyrm_type = OauthSiteType.where(slug: "bookwyrm").first
    unless bookwyrm_type
      Rails.logger.warn("FetchBookwyrmReviewsJob: no bookwyrm OauthSiteType found — run rails db:seed")
      reschedule && return if reschedulable
      return true
    end

    bookwyrm_type.oauth_sites.each do |oauth_site|
      next if oauth_site.access_token.blank?
      next if oauth_site.username.blank?
      sync_reviews_from(oauth_site, limit)
    rescue => e
      Rails.logger.error("FetchBookwyrmReviewsJob: error syncing #{oauth_site.base_url}: #{e.message}")
    end

    reschedule && return if reschedulable
    true
  end

  private

  def sync_reviews_from(oauth_site, limit)
    next_url = nil
    added = 0
    loop do
      items, next_url = fetch_outbox_page(oauth_site, next_url)
      break if items.empty?

      found_existing = false
      items.each do |item|
        next unless item.is_a?(Hash)
        # BookWyrm outbox returns review objects directly (not wrapped in Create activities)
        object = item["object"].is_a?(Hash) ? item["object"] : item
        next unless REVIEW_TYPES.include?(object["type"])

        source_url = object["id"]
        next if source_url.blank?

        if Review.exists?(source_url: source_url)
          found_existing = true
          break
        end

        create_review_from_activity(object, oauth_site)
        added += 1
        break if added >= limit
      end

      break if found_existing || next_url.nil? || added >= limit
    end
  end

  def fetch_outbox_page(oauth_site, page_url = nil)
    url = page_url || "#{oauth_site.base_url}/user/#{oauth_site.username}/outbox?page=true"
    response = HTTParty.get(
      url,
      headers: {
        "Accept" => "application/json",
        "Authorization" => "Bearer #{oauth_site.access_token}"
      },
      timeout: REQUEST_TIMEOUT
    )

    return [], nil unless response.success?

    body = JSON.parse(response.body)
    items = body["orderedItems"] || []
    next_url = body["next"]
    [items, next_url]
  rescue => e
    Rails.logger.error("FetchBookwyrmReviewsJob: HTTP error fetching #{url}: #{e.message}")
    [[], nil]
  end

  def create_review_from_activity(object, oauth_site)
    source_url = object["id"]
    html_content = object["content"].to_s
    rating = object["rating"]
    book_url = object["inReplyToBook"]

    markdown = build_markdown(html_content, rating, book_url, object["name"].presence)
    title = build_title(object, oauth_site)
    private_review = !public_activity?(object)

    Review.create!(
      title: title,
      string_data: markdown,
      rating: rating,
      source_url: source_url,
      private: private_review,
      sensitive: object["sensitive"] == true
    )
  rescue => e
    Rails.logger.error("FetchBookwyrmReviewsJob: failed to save review for #{source_url}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
  end

  def build_markdown(html_content, rating, book_url, review_name)
    lines = []
    lines << "## #{review_name}" if review_name.present?
    lines << "**Rating:** #{rating}/5" if rating.present?
    lines << "**Book:** #{book_url}" if book_url.present?
    body = ReverseMarkdown.convert(html_content, unknown_tags: :bypass).strip
    lines << body if body.present?
    lines.join("\n\n")
  end

  def build_title(object, oauth_site)
    book_title = fetch_book_title(object["inReplyToBook"])
    I18n.t("jobs.bookwyrm.review_title", author: "@#{oauth_site.username}", book_title: book_title)
  end

  def fetch_book_title(book_url)
    return I18n.t("jobs.bookwyrm.unknown_book") if book_url.blank?
    response = HTTParty.get(
      book_url,
      headers: {"Accept" => "application/activity+json"},
      timeout: REQUEST_TIMEOUT
    )
    return I18n.t("jobs.bookwyrm.unknown_book") unless response.success?
    JSON.parse(response.body)["name"].presence || I18n.t("jobs.bookwyrm.unknown_book")
  rescue => e
    Rails.logger.warn("FetchBookwyrmReviewsJob: could not fetch book title from #{book_url}: #{e.message}")
    I18n.t("jobs.bookwyrm.unknown_book")
  end

  def public_activity?(object)
    to = Array(object["to"])
    cc = Array(object["cc"])
    (to + cc).include?(PUBLIC_AUDIENCE)
  end

  def reschedule
    already_queued = Delayed::Backend::Mongoid::Job
      .exists?(failed_at: nil, handler: /job_class: FetchBookwyrmReviewsJob\n/)
    self.class.set(wait: 12.hours).perform_later(reschedulable: true) unless already_queued
  end
end
