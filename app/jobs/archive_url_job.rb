require "uri"
require "tempfile"
require "digest"

class ArchiveUrlJob < ApplicationJob
  include BackupBrain::ArchiveTools
  include BackupBrain::Archiver

  queue_as :low_priority

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def perform(bookmark_id:)
    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    return false unless bookmark

    unless ENV["I_INSTALLED_READER"] == "true" && BackupBrain::ToolDispatcher.instance.viable_install?
      Rails.logger.warn("ArchiveUrlJob can't run without reader installed")
      return false
    end

    begin
      tempfile        = download(bookmark)
      markdown_string = BackupBrain::ToolDispatcher.instance.run(bookmark.url, tempfile) # potentially raises
      record_failed_attempt(bookmark, 600) if markdown_string.blank?
      markdown_string = fully_qualify_urls(markdown_string, bookmark)
      tempfile.close

      bookmark.archives << Archive.new(
        mime_type: "text/markdown",
        string_data: markdown_string
      )
      bookmark.save!
      bookmark
    rescue BackupBrain::Errors::UnarchivableUrl => e
      Rails.logger.error(e.message)
      begin
        tempfile.close
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
        headers: {"User-Agent" => BackupBrain::ArchiveTools::USER_AGENT_STRING})
      if response.code < 400
        file = Tempfile.new(bookmark._id.to_s)
        file.write(response
                    .body
                    .encode!("UTF-8", "binary",
                      invalid: :replace,
                      undef: :replace,
                      replace: ""))
        file.flush
        file
      else
        record_failed_attempt(bookmark, response.code)
      end
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
      record_failed_attempt(bookmark, 599)
    end
  end
end
