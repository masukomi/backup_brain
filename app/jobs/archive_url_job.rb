require "uri"
require "tempfile"
require "digest"
require "json"

class ArchiveUrlJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::Archiver

  queue_as :low_priority

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def perform(bookmark_id:)
    Rails.logger.info("ArchiveUrlJob starting for bookmark #{bookmark_id}")

    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    unless bookmark
      Rails.logger.warn("ArchiveUrlJob: bookmark #{bookmark_id} not found")
      return false
    end

    if bookmark.api_archive_source.present?
      perform_api_archival(bookmark)
    else
      perform_standard_archival(bookmark)
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
    record_failed_attempt(bookmark, 599, should_raise: false)
  rescue => e
    Rails.logger.warn("couldn't archive #{bookmark.url} - #{e.message}")
    nil
  end

  def perform_standard_archival(bookmark)
    unless begin
      Setting.get_value_of_key("enable_archiving") == true
    rescue
      false
    end
      Rails.logger.warn("ArchiveUrlJob: enable_archiving setting is not true")
      return false
    end
    unless BackupBrain::ToolDispatcher.instance.viable_install?
      Rails.logger.warn("ArchiveUrlJob: reader binary not found or not executable")
      return false
    end

    prior_failure_count = bookmark.failed_archive_attempts.count

    begin
      dispatcher = BackupBrain::ToolDispatcher.instance
      tempfile, hero_image_url = dispatcher.handles_download?(bookmark.url) ? [nil, nil] : download(bookmark)
      raw_output = dispatcher.run(bookmark.url, tempfile) # raises on non-zero exit
      markdown_string = interpret_tool_output(raw_output, bookmark)
      record_failed_attempt(bookmark, 600) if markdown_string.blank?
      if hero_image_url.present?
        # prepend the hero image
        markdown_string = "![Hero Image](#{hero_image_url})\n\n#{markdown_string}"
      end
      markdown_string = fully_qualify_urls(markdown_string, bookmark)
      tempfile&.close

      archive = Archive.new(mime_type: "text/markdown", string_data: markdown_string)
      if hero_image_url.present?
        first_line = markdown_string.split(/\r\n|\n/).first.to_s
        _line, image_url_hashes = Archive.extract_image_links_from_line(first_line, false)
        if image_url_hashes.any?
          candidate = image_url_hashes.values.first[:url]
          archive.hero_image_path = candidate if candidate.start_with?(archive_web_path_for_doc(bookmark))
        end
      end
      archive.audio_urls.each { |url| archive.add_media_object(url, simple_type: "audio") }
      archive.video_urls.each { |url| archive.add_media_object(url, simple_type: "video") }
      bookmark.archives << archive
      bookmark.failed_archive_attempts.clear
      ContentTrigger.apply_triggers(test_string: archive.string_data, apply_to: bookmark)
      bookmark.save!
      if archive.media_objects.any? { |mo| mo.simple_type == "audio" }
        GenerateHeroImageJob.perform_later(
          bookmark_id: bookmark._id.to_s,
          archive_id: archive._id.to_s
        )
      end
      bookmark
    rescue BackupBrain::Errors::UnarchivableUrl => e
      Rails.logger.error(e.message)
      begin
        tempfile&.close
      rescue
        nil
      end
      # Only record a new failure if nothing inside the begin block already did.
      # (record_failed_attempt raises UnarchivableUrl after saving, so a duplicate
      # would occur if we recorded unconditionally here.)
      # 601 = archiving tool exited non-zero (distinct from HTTP codes and 599/600)
      if bookmark.failed_archive_attempts.count == prior_failure_count
        record_failed_attempt(bookmark, 601, should_raise: false)
      end
      nil
    end
  end

  def perform_api_archival(bookmark)
    source = bookmark.api_archive_source
    oauth_site = source.oauth_site
    if oauth_site.blank?
      Rails.logger.warn("ArchiveUrlJob: OauthSite for bookmark #{bookmark.id} is missing. Falling back to standard URL archiving.")
      return perform_standard_archival(bookmark)
    end

    case source.service
    when "mastodon"
      rearchive_mastodon(bookmark, oauth_site, source)
    when "misskey"
      rearchive_misskey(bookmark, oauth_site, source)
    else
      Rails.logger.warn("ArchiveUrlJob: Unknown API service #{source.service} for bookmark #{bookmark.id}. Falling back to standard URL archiving.")
      perform_standard_archival(bookmark)
    end
  end

  def rearchive_mastodon(bookmark, oauth_site, source)
    url = "#{oauth_site.base_url}/api/v1/statuses/#{source.remote_id}"
    res = HTTParty.get(url,
      headers: {"Authorization" => "Bearer #{oauth_site.access_token}"},
      timeout: 30)

    unless res.success?
      record_failed_attempt(bookmark, res.code, message: "Failed to fetch Mastodon status from API: #{res.code}", should_raise: false)
      return nil
    end

    status = JSON.parse(res.body)
    html_content = status["content"].to_s

    archive = html_to_archive(bookmark, html_content) ||
      Archive.new(mime_type: "text/markdown", string_data: "")

    job = FetchMastodonBookmarksJob.new
    job.send(:append_media_attachments, status["media_attachments"], archive, bookmark, oauth_site.access_token)

    finalize_and_save_api_archive(bookmark, archive, oauth_site)
  rescue => e
    Rails.logger.error("ArchiveUrlJob Mastodon API re-archiving failed for bookmark #{bookmark.id}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    record_failed_attempt(bookmark, 601, message: "Mastodon API error: #{e.message}", should_raise: false)
    nil
  end

  def rearchive_misskey(bookmark, oauth_site, source)
    payload = {i: oauth_site.access_token, noteId: source.remote_id}
    res = HTTParty.post(
      "#{oauth_site.base_url}/api/notes/show",
      headers: {"Content-Type" => "application/json"},
      body: payload.to_json,
      timeout: 30
    )

    unless res.success?
      record_failed_attempt(bookmark, res.code, message: "Failed to fetch Misskey note from API: #{res.code}", should_raise: false)
      return nil
    end

    note = JSON.parse(res.body)
    text_content = note["text"].to_s

    archive = Archive.new(mime_type: "text/markdown", string_data: text_content)

    job = FetchMisskeyBookmarksJob.new
    job.send(:append_media_files, note["files"], archive, bookmark)
    job.send(:embed_youtube_videos, archive)

    finalize_and_save_api_archive(bookmark, archive, oauth_site)
  rescue => e
    Rails.logger.error("ArchiveUrlJob Misskey API re-archiving failed for bookmark #{bookmark.id}: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    record_failed_attempt(bookmark, 601, message: "Misskey API error: #{e.message}", should_raise: false)
    nil
  end

  def finalize_and_save_api_archive(bookmark, archive, oauth_site)
    return nil if archive.string_data.blank?

    archive.metadata = generate_metadata_for_oauth_site(oauth_site)
    archive.audio_urls.each { |url| archive.add_media_object(url, simple_type: "audio") }
    archive.video_urls.each { |url| archive.add_media_object(url, simple_type: "video", sensitive: bookmark.sensitive) }
    archive.created_at = DateTime.now
    archive.updated_at = archive.created_at

    bookmark.archives << archive
    bookmark.failed_archive_attempts.clear
    ContentTrigger.apply_triggers(test_string: archive.string_data, apply_to: bookmark)
    bookmark.save!
    bookmark
  end

  def interpret_tool_output(raw_output, bookmark)
    result = JSON.parse(raw_output.to_s)
    case result["status"]
    when "SUCCESS"
      result["markdown"]
    when "ERROR"
      record_failed_attempt(
        bookmark, 601,
        error_message: result["error_message"],
        backtrace: result["backtrace"],
        additional_info: result["additional_info"]
      ) # raises UnarchivableUrl, caught by existing rescue in perform
    else
      raw_output
    end
  rescue JSON::ParserError
    raw_output # old-style tool (e.g. bin/reader) returning raw markdown
  end

  def download(bookmark)
    downloadable, error_code = url_downloadable?(bookmark.url, include_code: true)
    unless downloadable
      record_failed_attempt(bookmark, error_code,
        message: "Remote server prevented download. Status code: #{error_code}")
    end

    begin
      response = HTTParty.get(bookmark.url,
        verify: false,
        timeout: archival_requests_timeout,
        headers: BackupBrain::RequestHeaders.instance.headers_for(bookmark.url))
      if response.code < 400
        body = response.body.encode!("UTF-8", "binary",
          invalid: :replace,
          undef: :replace,
          replace: "")
        hero_image_url = BackupBrain::HeroImageFinder.find(body)
        file = Tempfile.new(bookmark._id.to_s)
        file.write(body)
        file.flush
        [file, hero_image_url]
      else
        record_failed_attempt(bookmark, response.code)
      end
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
      record_failed_attempt(bookmark, 599)
    end
  end
end
