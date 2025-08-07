require "uri"
require "tempfile"
require "open3"
require "digest"

class ArchiveUrlJob < ApplicationJob
  USER_AGENT_STRING = ENV.fetch("USER_AGENT_STRING", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36")

  include BackupBrain::ArchiveTools
  queue_as :low_priority # :default

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def perform(bookmark_id:)
    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    return false unless bookmark

    unless ENV["I_INSTALLED_READER"] == "true" && viable_reader_install?
      Rails.logger.warn("ArchiveUrlJob can't run without reader installed")
      return false
    end

    begin
      tempfile = download(bookmark)
      markdown_string = run_reader(tempfile) # potentially Raises
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
    # 599 Network Connect Timeout Error
    record_failed_attempt(bookmark, 599, should_raise: false)
  rescue => e
    Rails.logger.warn("couldn't archive #{bookmark.url} - #{e.message}")

    nil
  end

  def viable_reader_install?
    File.executable?(reader_path)
  end

  def reader_path
    Rails.root.join("bin/reader")
  end

  # downloads an image to
  # public/images/archivable/#{bookmark._id}/#{sha256_of_url}.#{extension}
  #
  # @param bookmark [Bookmark]
  # @param url [String] A fully qualified url
  #
  # @raise UnarchivableUrl
  # @raise StorageError
  def download_image(bookmark, url)
    # you'd never download a data:image url
    return url if url.start_with? "data:image"

    # see if its downloadable
    downloadable, error_code = url_downloadable?(url, include_code: true)
    unless downloadable
      # raise BackupBrain::Errors::UnarchivableUrl.new("foo")
      record_failed_attempt(bookmark, error_code,
        message: "Remote server prevented image download. Status code: #{error_code} URL: #{url.sub(/\?.*?$/, "?…<query_string>")}",
        should_raise: !(error_code > 399 && error_code < 500))
      # if it's a 404 variant don't raise and return our default missing image image url
      return MISSING_IMAGE_IMAGE_URL
    end

    # File.join because maybe someone will try and run this on Windows
    archive_folder_path = File.join(
      ARCHIVES_FOLDER,
      "bookmarks",
      bookmark._id.to_s
    )
    begin
      # create folder to store it (if doesn't exist)
      FileUtils.mkdir_p(archive_folder_path)
    rescue => e
      Rails.logger.warn("Failed to create folder to store archivable images")
      raise BackupBrain::Errors::StorageError.new(e.message)
    end
    local_name = archived_image_name(url)
    image_file_path = File.join(archive_folder_path, local_name)
    new_url = "/archives/bookmarks/#{bookmark._id}/#{local_name}"
    # no point in attempting to download if we already have it.
    # TODO: test if it's > 0 bytes
    return new_url if File.exist? image_file_path

    # attempt to download it
    begin
      File.open(image_file_path, "wx") do |file|
        file.binmode
        HTTParty.get(url,
          verify: false,
          follow_redirects: true,
          timeout: ARCHIVE_TIMEOUT,
          headers: {"User-Agent" => USER_AGENT_STRING}) do |fragment|
          file.write(fragment)
        end
      end
      # TODO check image size.
      # - Delete if 1x1 pixels (tracking image)
      # - return "" for new url
      # - remove image tag in calling function
    rescue => e
      # lots of things could have been thrown from the filesystem or HTTParty
      Rails.logger.warn("problem downloading/writing image from \"#{url}\" to \"#{image_file_path}\" - #{e.message}")
      raise e
    end
    new_url
  end

  def download(bookmark)
    # NOTE: the "reader" cli tool CAN download this itself,
    # but i want to have control over the User-Agent
    # and know that retries & redirects will be
    # handled well. So I'm downloading it with HTTParty.
    downloadable, error_code = url_downloadable?(bookmark.url, include_code: true)
    unless downloadable
      record_failed_attempt(bookmark, error_code,
        message: "Remote server prevented download. Status code: #{error_code}")
      # raises BackupBrain::Errors::UnarchivableUrl
    end

    begin
      response = HTTParty.get(bookmark.url,
        verify: false,
        timeout: ARCHIVE_TIMEOUT,
        headers: {"User-Agent" => USER_AGENT_STRING})
      if response.code < 400
        file = Tempfile.new(bookmark._id.to_s)

        # see https://thoughtbot.com/blog/fight-back-utf-8-invalid-byte-sequences
        # for details on wtf is going on here.
        file.write(response
                    .body
                    .encode!("UTF-8", "binary",
                      invalid: :replace,
                      undef: :replace,
                      replace: ""))
        file
      else
        record_failed_attempt(bookmark, response.code)
      end
    rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
      # 599 Network Connect Timeout Error
      record_failed_attempt(bookmark, 599)
    end
  end

  def run_reader(tempfile)
    # Given that this is a single-user self-hosted site, it'd be pretty
    # weird for someone to create a malicious url to hack the system.
    # But it's possible they reused a password that got leaked
    # and now some a-hole is trying to hack into their stuff.
    # Incredibly unlikely, but hey. Best Practices are "BEST" practices
    # for a reason. We'll make sure to escape that input.

    # reader doesn't care if the file path ends in .html or not

    _, stdout, stderr, wait_thr = Open3.popen3(
      reader_path.to_path,
      "-o",
      "--image-mode",
      "none",
      tempfile.path
    )
    markdown_string = stdout.gets(nil)&.chomp
    stdout.close
    error_string = stderr.gets(nil)&.chomp # hopefully nil
    stderr.close
    exit_code = wait_thr.value
    return markdown_string if exit_code == 0
    raise BackupBrain::Errors::UnarchivableUrl.new("problems invoking reader: (Exit Code:  #{exit_code}) #{error_string}")
  end

  def fully_qualify_urls(markdown, bookmark)
    # ![text](/foo/bar.gif) -> [text](https://example.com/foo/bar.gif)
    # ![text](bar.gif) -> [text](https://example.com/bar.gif)
    # [text](#foo) -> [text](#foo)
    # the ! (image url) doesn't effect anything here

    return if markdown.nil? || (markdown.size == 0)
    uri = URI.parse(bookmark.url)
    # given bookmark.url of: "https://example.com/foo/bar.html"
    # uri.origin => "https://example.com"
    # File.dirname(bookmark.url) => "https://example.com/foo"
    domain    = uri.origin
    directory = get_directory_url(bookmark)

    # create a string buffer because it'll probably
    # be more efficent than tons of concatenation
    buffer = StringIO.new
    # iterate over each line
    markdown.split(/\r\n|\n/).each do |line|
      processed_line = process_md_links(bookmark, line, domain, directory)

      buffer.write(processed_line)
      buffer.write("\n")
    end
    buffer.string
  end

  # takes in a line, processes its simple [foo](bar) links
  # and returns the line.
  #
  # Processing involves
  # - fully qualifying urls (/foo -> https://example.com/foo)
  # - attempting to download any images
  # - replacing image urls with urls of archived versions
  #
  # @warning THIS IS NOT SCALEABLE
  #   The image archiving portion of this takes longer
  #   than you'd expect when we don't have the images already.
  #   It's fine for single user BUT…
  def process_md_links(bookmark, line, domain, directory)
    line, image_url_hashes = Archive.extract_image_links_from_line(line)
    # TODO handle src="/foo" and data="/foo" (the latter may be tricky)

    # NOTE: this weird-ass 2-stage function is because
    # it's nigh fucking impossible to write a regexp
    # that can handle [![](/foo.jpg)](/link/to/something)
    # when there are multiple links/images on the same line.
    # I gave up, and I acutally LIKE regexp.
    match_datas = line.to_enum(:scan, Archive::SIMPLE_MD_LINK_REGEXP).map { Regexp.last_match }
    return line if image_url_hashes.empty? && match_datas.empty?

    new_line = line.dup

    match_datas.each do |md|
      # #<MatchData "[link1](foo)" 1:"[link1](foo)" 2:"link1" 3:"foo">
      url = fully_qualify_path(md[3], domain, directory)
      new_line.sub!(md[1], "[#{md[2]}](#{url})")
      # would be extra work if there were multiple identical links on the same line
    end

    new_line = qualify_and_apply_image_url_hashes(bookmark, image_url_hashes, new_line, domain, directory)
  end

  # @param hashes [Hash] hash of sha256 hashes as keys
  #        and url strings as values
  # @param line [String] the line to replace sha256 hashes in
  #        with the fully qualified urls
  # @return modified string
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

  # because this is only used when we've matched that it's NOT
  # starting with http(s) I'm going to assume it's "/foo" or "foo"
  def fully_qualify_path(path, domain, directory)
    # note domain & directory do NOT have trailing slashes
    return (domain + path) if path.start_with? "/"
    return path if /^https?:\/\//.match? path.downcase
    return path if path.start_with? "data:image"
    # path may be ../foo/bar.jpg
    # but loading
    # https://example.com/bar/../foo/bar.jpg should work just fine
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
    url_sans_query_string = original_url.sub(/\?.*/, "")
    hex_digest = Digest::SHA2.hexdigest(url_sans_query_string) # => abc123
    extension = File.extname(url_sans_query_string) # => .jpg
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
