require "uri"
require "tempfile"
require "digest"

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

    unless ENV["I_INSTALLED_READER"] == "true"
      Rails.logger.warn("ArchiveUrlJob: I_INSTALLED_READER is not set to 'true'")
      return false
    end
    unless BackupBrain::ToolDispatcher.instance.viable_install?
      Rails.logger.warn("ArchiveUrlJob: reader binary not found or not executable")
      return false
    end

    begin
      dispatcher               = BackupBrain::ToolDispatcher.instance
      tempfile, hero_image_url = dispatcher.handles_download?(bookmark.url) ? [nil, nil] : download(bookmark)
      markdown_string          = dispatcher.run(bookmark.url, tempfile) # potentially raises
      record_failed_attempt(bookmark, 600) if markdown_string.blank?
      if hero_image_url.present?
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
      bookmark.archives << archive
      bookmark.save!
      if (video_id = BackupBrain::YouTube.video_id(bookmark.url))
        YouTubeTranscriptionJob.perform_later(
          bookmark_id: bookmark._id.to_s,
          video_id: video_id,
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
      nil
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
    record_failed_attempt(bookmark, 599, should_raise: false)
  rescue => e
    Rails.logger.warn("couldn't archive #{bookmark.url} - #{e.message}")
    nil
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
        timeout: BackupBrain::ArchiveTools::ARCHIVE_TIMEOUT,
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
