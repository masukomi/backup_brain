require "uri"
require "digest"

module BackupBrain
  # Shared archiving logic used by jobs that need to create Archive documents
  # from markdown or HTML content, qualify URLs, and locally cache images.
  module Archiver
    USER_AGENT_STRING     = ENV.fetch("USER_AGENT_STRING", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36")
    ARCHIVE_TIMEOUT       = ENV.fetch("ARCHIVE_TIMEOUT", "10").to_i
    MISSING_IMAGE_IMAGE_URL = ENV.fetch("MISSING_IMAGE_IMAGE_URL", "/images/icons/missing_image_image.svg")
    MISSING_AUDIO_AUDIO_URL = ENV.fetch("MISSING_AUDIO_AUDIO_URL", "/audio/missing_audio_audio.mp3")

    # Converts an HTML string to a markdown Archive document.
    # Fully qualifies relative URLs and locally caches any images.
    #
    # @param bookmark [Bookmark] used for context (URL, image storage path)
    # @param html_string [String] raw HTML to convert
    # @return [Archive, nil]
    def html_to_archive(bookmark, html_string)
      return nil if html_string.blank?
      markdown = ReverseMarkdown.convert(html_string, unknown_tags: :bypass).strip
      return nil if markdown.blank?
      markdown = fully_qualify_urls(markdown, bookmark)
      Archive.new(mime_type: "text/markdown", string_data: markdown)
    end

    def fully_qualify_urls(markdown, bookmark)
      return if markdown.nil? || markdown.size == 0
      uri       = URI.parse(bookmark.url)
      domain    = uri.origin
      directory = get_directory_url(bookmark)

      buffer = StringIO.new
      markdown.split(/\r\n|\n/).each do |line|
        buffer.write(process_md_links(bookmark, line, domain, directory))
        buffer.write("\n")
      end
      buffer.string
    end

    def process_md_links(bookmark, line, domain, directory)
      line, image_url_hashes = Archive.extract_image_links_from_line(line)
      line, audio_url_hashes = Archive.extract_audio_urls_from_line(line)
      match_datas = line.to_enum(:scan, Archive::SIMPLE_MD_LINK_REGEXP).map { Regexp.last_match }
      return line if image_url_hashes.empty? && audio_url_hashes.empty? && match_datas.empty?

      new_line = line.dup
      match_datas.each do |md|
        url = fully_qualify_path(md[3], domain, directory)
        new_line.sub!(md[1], "[#{md[2]}](#{url})")
      end
      new_line = qualify_and_apply_image_url_hashes(bookmark, image_url_hashes, new_line, domain, directory)
      qualify_and_apply_audio_url_hashes(bookmark, audio_url_hashes, new_line, domain, directory)
    end

    def qualify_and_apply_image_url_hashes(bookmark, hashes, line, domain, directory)
      hashes.each do |sha, url|
        if url != MISSING_IMAGE_IMAGE_URL && !url.start_with?("/images/archival/#{bookmark._id}/")
          full_url = fully_qualify_path(url, domain, directory)
          hashes[sha] = download_image(bookmark, full_url)
        end
        line.sub!(sha, "![](#{hashes[sha]})")
      end
      line
    end

    def qualify_and_apply_audio_url_hashes(bookmark, hashes, line, domain, directory)
      hashes.each do |sha, url|
        if url != MISSING_AUDIO_AUDIO_URL && !url.start_with?(archive_web_path_for_doc(bookmark))
          full_url = fully_qualify_path(url, domain, directory)
          hashes[sha] = download_audio(bookmark, full_url)
        end
        line.sub!(sha, hashes[sha])
      end
      line
    end

    def download_audio(bookmark, url)
      downloadable, error_code = url_downloadable?(url, include_code: true)
      unless downloadable
        record_failed_attempt(bookmark, error_code,
          message: "Remote server prevented audio download. Status code: #{error_code} URL: #{url.sub(/\?.*?$/, "?…<query_string>")}",
          should_raise: false)
        return MISSING_AUDIO_AUDIO_URL
      end

      download_asset(bookmark, url, asset_label: "audio")
    rescue => e
      url
    end

    def download_image(bookmark, url)
      return url if url.start_with?("data:image")

      downloadable, error_code = url_downloadable?(url, include_code: true)
      unless downloadable
        record_failed_attempt(bookmark, error_code,
          message: "Remote server prevented image download. Status code: #{error_code} URL: #{url.sub(/\?.*?$/, "?…<query_string>")}",
          should_raise: !(error_code > 399 && error_code < 500))
        return MISSING_IMAGE_IMAGE_URL
      end

      download_asset(bookmark, url, asset_label: "image")
    end

    # Creates the archive directory, downloads +url+ to a local file named by
    # SHA256+extension, and returns the local web path.
    # Raises BackupBrain::Errors::StorageError if the directory cannot be created.
    # Logs and re-raises any download/write errors so callers can decide how to
    # handle them.
    def download_asset(bookmark, url, asset_label:)
      archive_folder_path = archive_folder_path_for_doc(bookmark)
      begin
        FileUtils.mkdir_p(archive_folder_path)
      rescue => e
        Rails.logger.warn("Failed to create folder to store archived #{asset_label}")
        raise BackupBrain::Errors::StorageError.new(e.message)
      end

      local_name = archived_image_name(url)
      file_path  = File.join(archive_folder_path, local_name)
      new_url    = archive_web_path_for_doc(bookmark) + "/#{local_name}"
      return new_url if File.exist?(file_path)

      begin
        File.open(file_path, "wx") do |file|
          file.binmode
          HTTParty.get(url,
            verify: false,
            follow_redirects: true,
            timeout: ARCHIVE_TIMEOUT,
            headers: {"User-Agent" => USER_AGENT_STRING}) do |fragment|
            file.write(fragment)
          end
        end
      rescue => e
        Rails.logger.warn("problem downloading/writing #{asset_label} from \"#{url}\" to \"#{file_path}\" - #{e.message}")
        raise e
      end
      new_url
    end

    def fully_qualify_path(path, domain, directory)
      return (domain + path) if path.start_with?("/")
      return path if /^https?:\/\//.match?(path.downcase)
      return path if path.start_with?("data:image")
      "#{directory}/#{path}"
    end

    def get_directory_url(bookmark)
      qs_less = bookmark.url.sub(/\?.*/, "")
      if !qs_less.end_with?("/")
        File.dirname(bookmark.url)
      else
        qs_less.sub(/\/$/, "")
      end
    end

    def archived_image_name(original_url)
      url_sans_trailing_crap = original_url.sub(/\?.*/, "").sub(/#.*$/, "")
      hex_digest = Digest::SHA2.hexdigest(url_sans_trailing_crap)
      extension  = File.extname(url_sans_trailing_crap).downcase
      "#{hex_digest}#{extension}"
    end

    def record_failed_attempt(bookmark, error_code, message: nil, should_raise: true)
      failed_attempt = FailedArchiveAttempt.new(status_code: error_code)
      bookmark.failed_archive_attempts << failed_attempt
      bookmark.save!
      message ||= "Failed to download #{bookmark.url} - #{error_code}"
      Rails.logger.info(message)
      raise BackupBrain::Errors::UnarchivableUrl.new(message) if should_raise
    end
  end
end
