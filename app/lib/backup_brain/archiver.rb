require "uri"
require "digest"
require "open3"
require "rack/mime"

module BackupBrain
  # Shared archiving logic used by jobs that need to create Archive documents
  # from markdown or HTML content, qualify URLs, and locally cache images.
  module Archiver
    ARCHIVE_TIMEOUT = ENV.fetch("ARCHIVE_TIMEOUT", "10").to_i
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
      archive = Archive.new(mime_type: "text/markdown")
      markdown = fully_qualify_urls(markdown, bookmark, archive_id: archive._id.to_s)
      archive.string_data = markdown
      archive
    end

    def fully_qualify_urls(markdown, bookmark, archive_id: nil)
      return if markdown.nil? || markdown.size == 0
      uri = URI.parse(bookmark.url)
      domain = uri.origin
      directory = get_directory_url(bookmark)

      buffer = StringIO.new
      markdown.split(/\r\n|\n/).each do |line|
        buffer.write(process_media_links(bookmark, line, domain, directory, archive_id: archive_id))
        buffer.write("\n")
      end
      buffer.string
    end

    def process_media_links(bookmark, line, domain, directory, archive_id: nil)
      line, image_url_hashes = Archive.extract_image_links_from_line(line)
      line, audio_url_hashes = Archive.extract_audio_urls_from_line(line)
      # NOTE: not handling video urls because we don't suport archiving
      # video owing to the space restrictions & YouTube fighting video downloads
      match_datas = line.to_enum(:scan, Archive::SIMPLE_MD_LINK_REGEXP).map { Regexp.last_match }
      return line if image_url_hashes.empty? && audio_url_hashes.empty? && match_datas.empty?

      new_line = line.dup
      match_datas.each do |md|
        url = fully_qualify_path(md[3], domain, directory)
        new_line.sub!(md[1], "[#{md[2]}](#{url})")
      end
      new_line = qualify_and_apply_image_url_hashes(bookmark, image_url_hashes, new_line, domain, directory)
      qualify_and_apply_audio_url_hashes(bookmark, audio_url_hashes, new_line, domain, directory, archive_id: archive_id)
    end

    def qualify_and_apply_image_url_hashes(bookmark, hashes, line, domain, directory)
      hashes.each do |sha, url_data|
        url = url_data[:url]
        extension = url_data[:extension]
        if url != MISSING_IMAGE_IMAGE_URL && !url.start_with?("/images/archival/#{bookmark._id}/")
          full_url = fully_qualify_path(url, domain, directory)
          url = download_image(bookmark, full_url, extension: extension)
        end
        line.sub!(sha, "![](#{url})")
      end
      line
    end

    def qualify_and_apply_audio_url_hashes(bookmark, hashes, line, domain, directory, archive_id: nil)
      hashes.each do |sha, url_data|
        url = url_data[:url]
        extension = url_data[:extension]
        if url != MISSING_AUDIO_AUDIO_URL && !url.start_with?(archive_web_path_for_doc(bookmark))
          full_url = fully_qualify_path(url, domain, directory)
          url = download_audio(bookmark, full_url, extension: extension)
        end
        line.sub!(sha, url)
        if url == MISSING_AUDIO_AUDIO_URL
          missing_mime = Rack::Mime.mime_type(File.extname(MISSING_AUDIO_AUDIO_URL))
          line.sub!(/\btype=(["'])audio\/[^"']+\1/, "type=\\1#{missing_mime}\\1")
        end
      end
      line
    end

    def download_audio(bookmark, url, extension: nil)
      if streaming_url?(url)
        return download_audio_stream(bookmark, url, extension: extension)
      end

      downloadable, error_code = url_downloadable?(url, include_code: true)
      unless downloadable
        record_failed_attempt(bookmark, error_code,
          message: "Remote server prevented audio download. Status code: #{error_code} URL: #{url.sub(/\?.*?$/, "?…<query_string>")}",
          should_raise: false)
        return MISSING_AUDIO_AUDIO_URL
      end

      download_asset(bookmark, url, asset_label: "audio", extension: extension)
    rescue
      url
    end

    # Downloads an HLS (.m3u8) or MPEG-DASH (.mpd) audio stream using ffmpeg,
    # saves the result locally, and returns the local web path.
    # Falls back to the original URL if ffmpeg fails.
    def download_audio_stream(bookmark, url, extension: nil)
      archive_folder_path = archive_folder_path_for_doc(bookmark)
      begin
        FileUtils.mkdir_p(archive_folder_path)
      rescue => e
        Rails.logger.warn("Failed to create folder to store archived audio stream")
        raise BackupBrain::Errors::StorageError.new(e.message)
      end

      ext = extension.presence || ".mp3"
      ext = ".#{ext}" unless ext.start_with?(".")
      local_name = archived_image_name(url, ext)
      file_path = File.join(archive_folder_path, local_name)
      new_url = archive_web_path_for_doc(bookmark) + "/#{local_name}"
      return new_url if File.exist?(file_path)

      _stdout, stderr, status = Open3.capture3(
        "ffmpeg", "-i", url, "-acodec", "copy", "-vn", file_path
      )
      unless status.success? && File.exist?(file_path)
        Rails.logger.warn("ffmpeg failed to download audio stream from #{url}: #{stderr.strip}")
        return url
      end

      new_url
    rescue => e
      Rails.logger.warn("Error downloading audio stream from #{url}: #{e.message}")
      url
    end

    def download_image(bookmark, url, extension: nil)
      return url if url.start_with?("data:image")

      downloadable, error_code = url_downloadable?(url, include_code: true)
      unless downloadable
        record_failed_attempt(bookmark, error_code,
          message: "Remote server prevented image download. Status code: #{error_code} URL: #{url.sub(/\?.*?$/, "?…<query_string>")}",
          should_raise: !(error_code > 399 && error_code < 500))
        return MISSING_IMAGE_IMAGE_URL
      end

      download_asset(bookmark, url, asset_label: "image", extension: extension)
    end

    # Creates the archive directory, downloads +url+ to a local file named by
    # SHA256+extension, and returns the local web path.
    # Raises BackupBrain::Errors::StorageError if the directory cannot be created.
    # Logs and re-raises any download/write errors so callers can decide how to
    # handle them.
    #
    # When +extension+ is nil (type unknown), checks for a previously-detected file
    # via glob, downloads to a bare SHA256 name, then runs +detect_file_extension+
    # and renames the file before returning.
    def download_asset(bookmark, url, asset_label:, extension: nil)
      archive_folder_path = archive_folder_path_for_doc(bookmark)
      begin
        FileUtils.mkdir_p(archive_folder_path)
      rescue => e
        Rails.logger.warn("Failed to create folder to store archived #{asset_label}")
        raise BackupBrain::Errors::StorageError.new(e.message)
      end

      local_name = archived_image_name(url, extension)
      file_path = File.join(archive_folder_path, local_name)
      new_url = archive_web_path_for_doc(bookmark) + "/#{local_name}"
      needs_detection = File.extname(local_name).empty?

      if needs_detection
        existing = Dir.glob("#{file_path}.*").first
        return archive_web_path_for_doc(bookmark) + "/#{File.basename(existing)}" if existing
      end

      return new_url if File.exist?(file_path)

      http_response = nil
      begin
        File.open(file_path, "wx") do |file|
          file.binmode
          http_response = HTTParty.get(url,
            verify: false,
            follow_redirects: true,
            timeout: ARCHIVE_TIMEOUT,
            headers: BackupBrain::RequestHeaders.instance.headers_for(url)) do |fragment|
            file.write(fragment)
          end
        end
      rescue => e
        Rails.logger.warn("problem downloading/writing #{asset_label} from \"#{url}\" to \"#{file_path}\" - #{e.message}")
        raise e
      end

      if needs_detection
        # Prefer the server's Content-Type header; fall back to file(1) inspection.
        content_type = http_response.respond_to?(:headers) ? http_response.headers["content-type"].to_s : ""
        detected = Archive.extension_for_mime_type(content_type)
        detected = detect_file_extension(file_path) if detected.blank?
        if detected.present?
          new_name = "#{local_name}#{detected}"
          File.rename(file_path, File.join(archive_folder_path, new_name))
          return archive_web_path_for_doc(bookmark) + "/#{new_name}"
        end
      end

      new_url
    end

    def detect_file_extension(file_path)
      mime, = Open3.capture2("file", "-b", "--mime-type", file_path)
      mime = mime.strip
      mime = mime.sub(%r{\Aaudio/x-}, "audio/")
      Archive.extension_for_mime_type(mime)
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

    # Builds a local filename for a cached asset: SHA256 digest + extension.
    #
    # When a URL has no meaningful path (the identity is entirely in the query
    # string, e.g. https://stream.example.com/?t=TOKEN), the full URL including
    # query string is hashed so different assets on the same host get unique names.
    # Otherwise the query string is stripped before hashing (existing behaviour).
    #
    # The +extension+ argument takes priority over the extension derived from the URL.
    def archived_image_name(original_url, extension = nil)
      uri = URI.parse(original_url)
      hash_url = (uri.path.empty? || uri.path == "/") ?
        original_url :
        original_url.sub(/\?.*/, "").sub(/#.*$/, "")
      hex_digest = Digest::SHA2.hexdigest(hash_url)
      ext = if extension.present?
        extension.start_with?(".") ? extension.downcase : ".#{extension.downcase}"
      elsif uri.path.empty? || uri.path == "/"
        ""
      else
        File.extname(original_url.sub(/\?.*/, "").sub(/#.*$/, "")).downcase
      end
      "#{hex_digest}#{ext}"
    rescue URI::InvalidURIError
      "#{Digest::SHA2.hexdigest(original_url)}#{extension}"
    end

    # Returns true if +url+ points to an HLS or MPEG-DASH manifest
    # (i.e. a segmented stream that requires ffmpeg to download).
    def streaming_url?(url)
      path = URI.parse(url).path.to_s
      path.match?(/\.m3u8\z/i) || path.match?(/\.mpd\z/i)
    rescue URI::InvalidURIError
      false
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
