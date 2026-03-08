class FetchMastodonBookmarksJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::Archiver

  queue_as :low_priority

  MASTODON_TAG = "mastodon_bookmark"
  TITLE_TIMESTAMP_FORMAT = "%Y/%m/%d %H:%M"
  DESCRIPTION_CHAR_LIMIT = 500
  TITLE_CHAR_LIMIT = 80
  REQUEST_TIMEOUT = 30

  def perform(reschedulable: true)
    manual_perform(reschedulable)
  end

  def manual_perform(rescheduleable = false, limit: 1000)
    mastodon_type = OauthSiteType.where(slug: "mastodon").first
    unless mastodon_type
      Rails.logger.warn("FetchMastodonBookmarksJob: no mastodon OauthSiteType found — run rails db:seed")
      if rescheduleable
        reschedule && return
      else
        return true
      end
    end

    user = User.first
    unless user
      Rails.logger.warn("FetchMastodonBookmarksJob: no user found, skipping")
      if rescheduleable
        reschedule && return
      else
        return true
      end
    end

    mastodon_type.oauth_sites.each do |oauth_site|
      next if oauth_site.access_token.blank?
      sync_bookmarks_from(oauth_site, user, limit)
    rescue => e
      Rails.logger.error("FetchMastodonBookmarksJob: error syncing #{oauth_site.base_url}: #{e.message}")
    end
    if rescheduleable
      reschedule && return
    else
      true
    end
  end

  private

  def sync_bookmarks_from(oauth_site, user, limit)
    next_url = nil
    added = 0
    loop do
      statuses, next_url = fetch_bookmarks_page(oauth_site.base_url, oauth_site.access_token, next_url)
      break if statuses.empty?

      found_existing = false
      statuses.each do |status|
        url = status["url"]
        next if url.blank?

        if Bookmark.exists?(url: url)
          found_existing = true
          break
        end

        create_bookmark_from_status(status, user, oauth_site)
        added += 1
        break if added >= limit
      end

      break if found_existing || next_url.nil? || added >= limit
    end
  end

  def fetch_bookmarks_page(base_url, access_token, page_url = nil)
    url = page_url || "#{base_url}/api/v1/bookmarks"
    response = HTTParty.get(url,
      headers: {"Authorization" => "Bearer #{access_token}"},
      timeout: REQUEST_TIMEOUT)

    return [], nil unless response.success?

    statuses = JSON.parse(response.body)
    next_url = parse_next_link(response.headers["link"])
    [statuses, next_url]
  rescue => e
    Rails.logger.error("FetchMastodonBookmarksJob: HTTP error fetching #{url}: #{e.message}")
    [[], nil]
  end

  def parse_next_link(link_header)
    return nil if link_header.blank?
    match = link_header.match(/<([^>]+)>;\s*rel="next"/)
    match&.[](1)
  end

  def create_bookmark_from_status(status, user, oauth_site)
    url          = status["url"]
    html_content = status["content"].to_s

    markdown    = ReverseMarkdown.convert(html_content, unknown_tags: :bypass).strip
    description = truncate_markdown(markdown)
    title       = build_title(html_content, status)

    bookmark = Bookmark.new(
      url: url,
      title: title,
      description: description,
      user: user,
      tags: [MASTODON_TAG]
    )
    # We already have the content — build an Archive from the status HTML
    # and skip the normal ArchiveUrlJob queue (which would 404 on private statuses).
    bookmark.suppress_auto_archive!

    Rails.logger.info("FetchMastodonBookmarksJob status keys: #{status.keys}")
    Rails.logger.info("FetchMastodonBookmarksJob media_attachments: #{status["media_attachments"].inspect}")

    # html_to_archive returns nil when the status has no text content
    # (e.g. media-only posts). Fall back to an empty archive so that
    # media attachments still get processed and saved.
    archive = html_to_archive(bookmark, html_content) ||
      Archive.new(mime_type: "text/markdown", string_data: "")

    append_media_attachments(status["media_attachments"], archive, bookmark, oauth_site.access_token)

    if archive.string_data.present?
      # dunno why I have to do this created_at & updated_at manually
      archive.created_at = DateTime.now
      archive.updated_at = archive.created_at
      bookmark.archives << archive
    end
    bookmark.save!
  rescue => e
    Rails.logger.error("FetchMastodonBookmarksJob: failed to save bookmark for #{url}: #{e.message}\n#{e.backtrace.first(15).join("\n")}")
  end

  # Downloads each media attachment using the authenticated Mastodon API and
  # appends a markdown image line to the archive for each one.
  #
  # - image: downloads the full-resolution url
  # - gifv/video: downloads the preview_url (a still frame, since mp4 can't render in markdown)
  # - audio/unknown: skipped
  def append_media_attachments(attachments, archive, bookmark, access_token)
    return if attachments.blank?

    image_lines = attachments.filter_map do |attachment|
      url = case attachment["type"]
      when "image"        then attachment["url"]
      when "gifv", "video" then attachment["preview_url"]
      end
      next if url.blank?

      local_url = download_media_attachment(url, bookmark, access_token)
      next if local_url.blank?

      alt = attachment["description"].to_s.strip.gsub(/[\[\]()]/, " ")
      "![#{alt}](#{local_url})"
    end

    return if image_lines.empty?
    archive.string_data = archive.string_data.rstrip + "\n\n" + image_lines.join("\n")
  end

  # Downloads a media attachment URL using the Bearer token and stores it
  # locally using the same SHA256-based naming scheme as other archived images.
  #
  # @return [String, nil] the local web path, or nil on failure
  def download_media_attachment(url, bookmark, access_token)
    local_name      = archived_image_name(url)
    folder_path     = archive_folder_path_for_doc(bookmark)
    image_file_path = File.join(folder_path, local_name)
    local_web_url   = archive_web_path_for_doc(bookmark) + "/#{local_name}"

    FileUtils.mkdir_p(folder_path)

    response = HTTParty.get(url,
      headers: {"Authorization" => "Bearer #{access_token}"},
      verify: false,
      follow_redirects: true,
      timeout: REQUEST_TIMEOUT)

    unless response.success?
      Rails.logger.warn("FetchMastodonBookmarksJob: media attachment returned #{response.code} for #{url}")
      return nil
    end

    File.binwrite(image_file_path, response.body)
    File.exist?(image_file_path) ? local_web_url : nil
  rescue => e
    Rails.logger.error("FetchMastodonBookmarksJob: failed to download media attachment #{url}: #{e.message}")
    nil
  end

  # TODO: make this username (@foo@bar.com) + status.created_at.strftime("???")
  def build_title(html_content, status)
    timestamp = DateTime.parse(status["created_at"]).strftime(TITLE_TIMESTAMP_FORMAT)
    author = status.dig("account", "display_name")
    author = "@#{status.dig("account", "acct")}" if author.blank?
    I18n.t("jobs.mastodon.bookmark_title", author: author, timestamp: timestamp)
  end

  # Truncates markdown to the first whitespace after the Nth character,
  # where N is counted only over characters that are not part of markdown
  # link syntax [text](url) url portions or image tags ![alt](url).
  #
  # Images are skipped entirely (not counted).
  # For links, only the visible link text is counted; the (url) part is skipped.
  def truncate_markdown(text, limit = DESCRIPTION_CHAR_LIMIT)
    return text if text.length <= limit

    count = 0
    i = 0

    while i < text.length
      break if count >= limit

      # Image: ![alt](url) — skip entirely, count nothing
      if text[i] == "!" && i + 1 < text.length && text[i + 1] == "["
        close_bracket = text.index("]", i + 2)
        if close_bracket && close_bracket + 1 < text.length && text[close_bracket + 1] == "("
          close_paren = text.index(")", close_bracket + 2)
          if close_paren
            i = close_paren + 1
            next
          end
        end
      # Didn't look like a valid image tag — count the ! and move on

      # Link: [text](url) — count the link text, skip the (url) part
      elsif text[i] == "["
        close_bracket = text.index("]", i + 1)
        if close_bracket && close_bracket + 1 < text.length && text[close_bracket + 1] == "("
          close_paren = text.index(")", close_bracket + 2)
          if close_paren
            link_text = text[(i + 1)...close_bracket]
            count += link_text.length
            i = close_paren + 1
            next
          end
        end
        # Didn't look like a valid link — count the [ and move on

      end
      count += 1
      i += 1
    end

    # Advance past any non-whitespace to avoid cutting mid-word
    i += 1 while i < text.length && !text[i].match?(/\s/)

    text[0, i]
  end

  def reschedule
    self.class.set(wait: 10.minutes).perform_later
  end
end
