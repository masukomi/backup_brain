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

      bookmark.archives << Archive.new(
        mime_type: "text/markdown",
        string_data: markdown_string
      )
      bookmark.save!
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
