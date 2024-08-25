require "uri"
require "tempfile"
require "open3"

class ArchiveUrlJob < ApplicationJob
  include BackupBrain::ArchiveTools
  queue_as :low_priority # :default

  SIMPLE_MD_LINK_REGEXP = /((\[.*?\])\(\s*?(?!https?:\/\/)(.*?)\s*?\))/i
  IMAGE_MD_LINK_REGEXP = /((\[.*?\])\(\s*?(?!https?:\/\/)(.*?)\s*?\))/i

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
  rescue Net::ReadTimeout
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

  def download(bookmark)
    # NOTE: the "reader" cli tool CAN download this itself,
    # but i want to have control over the User-Agent
    # and know that retries & redirects will be
    # handled well. So I'm downloading it with HTTParty.
    downloadable, error_code = url_downloadable?(bookmark.url, include_code: true)
    unless downloadable
      record_failed_attempt(bookmark, error_code,
        message: "Remote server prevented download. Status code: #{error_code}")
    end

    begin
      response = HTTParty.get(bookmark.url,
        verify: false,
        timeout: 5,
        headers: {"User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/104.0.5112.79 Safari/537.36"})
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
    rescue Net::ReadTimeout
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
      processed_line = process_md_links(SIMPLE_MD_LINK_REGEXP, line, domain, directory)
      processed_line = process_md_links(IMAGE_MD_LINK_REGEXP, processed_line, domain, directory)

      buffer.write(processed_line)
      buffer.write("\n")
    end
    buffer.string
  end

  # takes in a line, processes its simple [foo](bar) links
  # and returns the line.
  def process_md_links(regexp, line, domain, directory)
    # TODO handle src="/foo" and data="/foo" (the latter may be tricky)
    matches = line.match?(regexp)
    return line unless matches
    new_line = ""
    match_datas = line.to_enum(:scan, regexp).map { Regexp.last_match }
    first_match_start = (match_datas[0].offset(0)[0] - 1)
    new_line += line[0..first_match_start] unless first_match_start == -1

    match_datas.each_with_index do |m_d, index|
      # #<MatchData "[link1](foo)" 1:"[link1](foo)" 2:"[link1]" 3:"foo">
      post_match = m_d.offset(0)[1]

      new_line += m_d[2] + "(#{fully_qualify_path(m_d[3], domain, directory)})"

      has_next = match_datas.size > index + 1
      if !has_next
        new_line += line[post_match..]
        break # not needed, but makes behavior clearer
      else
        next_match_start = match_datas[index + 1].offset(0)[0] - 1
        new_line += line[post_match..next_match_start]
      end
    end
    # Yes, I DID just reimplement gsub 🤦‍♀️
    # The problem is that backreferences like '\2' aren't actually converted
    # into what they point to until AFTER the replacement is handled. It's weird.
    new_line
  end

  # because this is only used when we've matched that it's NOT
  # starting with http(s) I'm going to assume it's "/foo" or "foo"
  def fully_qualify_path(path, domain, directory)
    # note domain & directory do NOT have trailing slashes
    return (domain + path) if path.start_with? "/"
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

  def record_failed_attempt(bookmark, error_code, message: nil, should_raise: true)
    failed_attempt = FailedArchiveAttempt.new(status_code: error_code)
    bookmark.failed_archive_attempts << failed_attempt
    bookmark.save!
    message ||= "Failed to download #{bookmark.url} - #{error_code}"
    Rails.logger.warn(message)
    raise BackupBrain::Errors::UnarchivableUrl.new(message) if should_raise
  end
end
