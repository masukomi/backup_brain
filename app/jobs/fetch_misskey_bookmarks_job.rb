class FetchMisskeyBookmarksJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::Archiver

  queue_as :low_priority

  DEFAULT_TAGS = ["misskey_bookmark", I18n.t("tags.default_tags.fediverse_bookmark_tag")]
  TITLE_TIMESTAMP_FORMAT = "%Y/%m/%d %H:%M"
  DESCRIPTION_CHAR_LIMIT = 500
  REQUEST_TIMEOUT = 30

  def self.schedule_unless_pending
    already_queued = Delayed::Backend::Mongoid::Job
      .exists?(failed_at: nil, handler: /job_class: FetchMisskeyBookmarksJob\n/)
    perform_later(reschedulable: true) unless already_queued
  end

  def perform(reschedulable: true)
    manual_perform(reschedulable)
  end

  def manual_perform(rescheduleable = false, limit: 1000)
    misskey_type = OauthSiteType.where(slug: "misskey").first
    unless misskey_type
      Rails.logger.warn("FetchMisskeyBookmarksJob: no misskey OauthSiteType found — run rails db:seed")
      if rescheduleable
        reschedule && return
      else
        return true
      end
    end

    user = User.first
    unless user
      Rails.logger.warn("FetchMisskeyBookmarksJob: no user found, skipping")
      if rescheduleable
        reschedule && return
      else
        return true
      end
    end

    misskey_type.oauth_sites.each do |oauth_site|
      next if oauth_site.access_token.blank?
      sync_bookmarks_from(oauth_site, user, limit)
    rescue => e
      Rails.logger.error("FetchMisskeyBookmarksJob: error syncing #{oauth_site.base_url}: #{e.message}")
    end
    if rescheduleable
      reschedule && return
    else
      true
    end
  end

  private

  def sync_bookmarks_from(oauth_site, user, limit)
    cursor = nil
    added = 0
    loop do
      favorites = fetch_favorites_page(oauth_site.base_url, oauth_site.access_token, cursor)
      break if favorites.empty?

      found_existing = false
      favorites.each do |favorite|
        note = favorite["note"]
        next if note.blank?

        url = note_url(note, oauth_site.base_url)
        next if url.blank?

        if Bookmark.exists?(url: url)
          found_existing = true
          break
        end

        create_bookmark_from_note(note, user, oauth_site)
        added += 1
        break if added >= limit
      end

      break if found_existing || added >= limit
      cursor = favorites.last["id"]
    end
  end

  def fetch_favorites_page(base_url, access_token, cursor = nil)
    payload = {i: access_token, limit: 20}
    payload[:untilId] = cursor if cursor.present?

    response = HTTParty.post(
      "#{base_url}/api/i/favorites",
      headers: {"Content-Type" => "application/json"},
      body: payload.to_json,
      timeout: REQUEST_TIMEOUT
    )

    return [] unless response.success?
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("FetchMisskeyBookmarksJob: HTTP error fetching favorites from #{base_url}: #{e.message}")
    []
  end

  def note_url(note, base_url)
    note["url"].presence || "#{base_url}/notes/#{note["id"]}"
  end

  def create_bookmark_from_note(note, user, oauth_site)
    url = note_url(note, oauth_site.base_url)
    user_data = note["user"] || {}
    text_content = note["text"].to_s

    description = truncate_text(text_content)
    title = build_title(note)

    bookmark = Bookmark.new(
      url: url,
      title: title,
      description: description,
      user: user,
      tags: DEFAULT_TAGS
    )

    sma = find_or_create_sma_for(user_data, oauth_site.base_url)
    person = sma&.person || Person.where(social_media_profile_url: profile_url_for(user_data, oauth_site.base_url)).first
    bookmark.people << person if person.present?
    bookmark.social_media_accounts << sma if sma.present?

    bookmark.suppress_auto_archive!

    archive = Archive.new(mime_type: "text/markdown", string_data: text_content)
    append_media_files(note["files"], archive, bookmark)
    embed_youtube_videos(archive)

    if archive.string_data.present?
      archive.metadata = generate_metadata_for_oauth_site(oauth_site)
      archive.video_urls.each { |vurl| archive.add_media_object(vurl, simple_type: "video") }
      archive.created_at = DateTime.now
      archive.updated_at = archive.created_at
      bookmark.archives << archive
      ContentTrigger.apply_triggers(test_string: archive.string_data, apply_to: bookmark)
    end

    bookmark.save!
  rescue => e
    Rails.logger.error("FetchMisskeyBookmarksJob: failed to save bookmark for #{url}: #{e.message}\n#{e.backtrace.first(15).join("\n")}")
  end

  def append_media_files(files, archive, bookmark)
    return if files.blank?

    image_lines = files.filter_map do |file|
      download_url = case file["type"]
      when "Image" then file["url"]
      when "Video" then file["thumbnailUrl"]
      end
      next if download_url.blank?

      local_path = download_asset(bookmark, download_url, asset_label: "misskey_media")
      if local_path.present?
        alt = file["comment"].to_s.strip.gsub(/[\[\]()"]/, " ")
        "![#{alt}](#{local_path})"
      else
        "BB: Image archive failure for #{download_url}"
      end
    rescue => e
      Rails.logger.error("FetchMisskeyBookmarksJob: failed to download #{file["url"]}: #{e.message}")
      nil
    end

    return if image_lines.empty?
    archive.string_data = archive.string_data.rstrip + "\n\n" + image_lines.join("\n")
  end

  def find_or_create_sma_for(user_data, base_url)
    profile_url = profile_url_for(user_data, base_url)
    return nil if profile_url.blank?

    existing = SocialMediaAccount.where(profile_url: profile_url).first
    return existing if existing

    username = user_data["host"].present? ?
      "@#{user_data["username"]}@#{user_data["host"]}" :
      "@#{user_data["username"]}"

    sma = SocialMediaAccount.new(
      profile_url: profile_url,
      service: "misskey",
      username: username,
      type: "unknown"
    )
    sma.suppress_auto_archive_job!
    if sma.save
      ArchiveSocialMediaAccountJob.perform_later(
        social_media_account_id: sma.id.to_s,
        avatar_url: user_data["avatarUrl"],
        header_url: user_data["bannerUrl"],
        replace_description: true
      )
    end
    sma
  rescue => e
    Rails.logger.error("FetchMisskeyBookmarksJob: could not find/create SMA for #{profile_url}: #{e.message}")
    nil
  end

  def profile_url_for(user_data, base_url)
    return nil if user_data["username"].blank?
    if user_data["host"].present?
      "https://#{user_data["host"]}/@#{user_data["username"]}"
    else
      "#{base_url}/@#{user_data["username"]}"
    end
  end

  def build_title(note)
    timestamp = DateTime.parse(note["createdAt"]).strftime(TITLE_TIMESTAMP_FORMAT)
    user_data = note["user"] || {}
    author = user_data["name"].presence || "@#{user_data["username"]}"
    I18n.t("jobs.misskey.bookmark_title", author: author, timestamp: timestamp)
  end

  def truncate_text(text, limit = DESCRIPTION_CHAR_LIMIT)
    return text if text.length <= limit
    # Advance past any non-whitespace to avoid cutting mid-word
    i = limit
    i += 1 while i < text.length && !text[i].match?(/\s/)
    text[0, i]
  end

  def embed_youtube_videos(archive)
    seen_ids = []
    embeds = []

    archive.string_data.scan(BackupBrain::YouTube::URL_REGEXP) do
      id = $~[1]
      next if seen_ids.include?(id)
      seen_ids << id
      embeds << BackupBrain::YouTube.embed_html($~[0])
    end

    return if embeds.empty?
    archive.string_data = archive.string_data.rstrip + "\n\n" + embeds.join("\n\n")
  end

  def reschedule
    already_queued = Delayed::Backend::Mongoid::Job
      .exists?(failed_at: nil, locked_at: nil, handler: /job_class: FetchMisskeyBookmarksJob\n/)
    self.class.set(wait: 10.minutes).perform_later(reschedulable: true) unless already_queued
  end
end
