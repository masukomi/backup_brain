class Archive
  SIMPLE_MD_LINK_REGEXP = /(?<!!)(\[(.*?)\]\((.*?)\))/i
  IMAGE_MD_LINK_REGEXP = /((!\[.*?\])\(\s*?(.*?)\s*?\))/i
  AUDIO_EXTENSIONS = %w[mp3 m4a ogg oga wav flac opus aac].freeze

  # Static reverse map: MIME type → file extension.
  # Covers both standard and x- variants emitted by the file(1) CLI tool.
  # Used by extension_for_mime_type instead of Rack::Mime::MIME_TYPES.key so
  # that non-audio types (e.g. application/octet-stream → ".a") don't leak in.
  AUDIO_MIME_EXTENSION_MAP = {
    "audio/aac" => ".aac",
    "audio/flac" => ".flac",
    "audio/x-flac" => ".flac",
    "audio/mp4" => ".m4a",
    "audio/x-m4a" => ".m4a",
    "audio/mpeg" => ".mp3",
    "audio/x-mpeg" => ".mp3",
    "audio/ogg" => ".ogg",
    "audio/oga" => ".oga",
    "audio/opus" => ".opus",
    "audio/wav" => ".wav",
    "audio/x-wav" => ".wav",
    "audio/webm" => ".webm"
  }.freeze
  AUDIO_SRC_REGEXP = Regexp.new(
    'src=(["\'])((?:https?://|/|\.\./\./)?[^"\'\\s]+\\.(?:' +
    AUDIO_EXTENSIONS.join("|") +
    '))\\1',
    Regexp::IGNORECASE
  )

  VIDEO_EXTENSIONS = %w[mp4 m4v mkv mov avi webm ogv].freeze

  VIDEO_SRC_REGEXP = Regexp.new(
    'src=(["\'])((?:https?://|/|\.\./\./)?[^"\'\\s]+\\.(?:' +
    VIDEO_EXTENSIONS.join("|") +
    '))\\1',
    Regexp::IGNORECASE
  )

  YOUTUBE_URL_REGEXP = %r{https?://(?:www\.)?(?:youtube\.com/watch\?[^\s"'<>\)\[\]]+|youtu\.be/[^\s"'<>\)\[\]]+)}i

  include Mongoid::Document
  include Mongoid::Timestamps
  field :mime_type, type: String, default: "text/markdown"
  field :string_data, type: String
  field :manually_edited, type: Boolean, default: false
  field :transcription_ids, type: Array, default: []
  field :hero_image_path, type: String

  embedded_in :bookmark
  embeds_many :media_objects, cascade_callbacks: true

  # Returns the file extension (with leading dot) for a given MIME type string,
  # or nil if unknown. Relies on audio types registered in config/initializers/mime_types.rb.
  #
  # @param mime_type [String] e.g. "audio/wav" or "audio/ogg; codecs=opus"
  # @return [String, nil] e.g. ".wav", or nil
  def self.extension_for_mime_type(mime_type)
    base = mime_type.to_s.split(";").first&.strip&.downcase
    AUDIO_MIME_EXTENSION_MAP[base]
  end

  # extracts all the image links
  # - fully qualifies the URLs
  # - replaces them with a sha256 hash
  # - returns a hash where the keys are the sha256 hashes
  #   and the values are hashes with :url and :extension keys
  #
  # @example
  #
  # my [![](foo.jpg)](/link/to/something) favorite [links](/links)
  # becomes
  # my [abc123](/link/to/something) favorite [links](/links)
  # and the hash
  # {"abc123" => {url: "foo.jpg", extension: ".jpg"}}
  #
  def self.extract_image_links_from_line(line, replace = true)
    match_datas = line
      .to_enum(:scan, Archive::IMAGE_MD_LINK_REGEXP)
      .map { Regexp.last_match }

    image_url_hashes = {}

    return [line, image_url_hashes] if match_datas.size == 0

    line_copy = line.dup
    match_datas.each_with_index do |md, index|
      url = md[3]
      sha_hash = Digest::SHA2.hexdigest(url)
      extension = File.extname(url.sub(/\?.*/, "").sub(/#.*$/, "")).downcase
      image_url_hashes[sha_hash] = {url: url, extension: extension}
      line_copy.sub!(md[1], sha_hash) if replace
    end
    [line_copy, image_url_hashes]
  end

  # Finds audio src URLs in HTML embedded within a markdown line.
  # Replaces each URL with a SHA256 hash placeholder and returns the
  # modified line and a hash mapping each placeholder to a {url:, extension:} hash.
  #
  # Two strategies are used:
  # 1. Extension-based: src URLs whose path ends in a supported audio extension.
  # 2. Type-based: <source> tags with type="audio/..." where the URL has no
  #    recognised audio extension (e.g. signed CDN URLs like audiochan.com).
  #
  # @param line [String]
  # @param replace [Boolean] whether to substitute URLs with hash placeholders
  # @return [Array(String, Hash)] modified line and {sha256 => {url:, extension:}} hash
  def self.extract_audio_urls_from_line(line, replace = true)
    audio_url_hashes = {}
    line_copy = line.dup

    # First pass: extension-based matching (existing behaviour)
    line.to_enum(:scan, Archive::AUDIO_SRC_REGEXP).map { Regexp.last_match }.each do |md|
      url = md[2]
      sha_hash = Digest::SHA2.hexdigest(url)
      extension = File.extname(url.sub(/\?.*/, "").sub(/#.*$/, "")).downcase
      audio_url_hashes[sha_hash] = {url: url, extension: extension}
      line_copy.sub!(url, sha_hash) if replace
    end

    # Second pass: <source type="audio/..."> tags whose src URL was not caught above.
    # Scan the original line so we see the real URLs, not the sha placeholders.
    line.scan(/<source\s+[^>]+>/i).each do |tag|
      mime_match = tag.match(/type=["'](audio\/[^"';]+)["']/i)
      next unless mime_match

      src_match = tag.match(/src=["']([^"']+)["']/i)
      next unless src_match

      url = src_match[1]
      next if audio_url_hashes.values.any? { |v| v[:url] == url }

      sha_hash = Digest::SHA2.hexdigest(url)
      mime = mime_match[1].strip
      extension = extension_for_mime_type(mime) || ""
      audio_url_hashes[sha_hash] = {url: url, extension: extension}
      line_copy.sub!(url, sha_hash) if replace
    end

    # Third pass: incomplete <source> tags (no closing > on this line).
    # Cannot see type=, so store extension: nil; download_asset will detect it.
    line.scan(/<source\b(?![^>]*>)[^>]*/i).each do |fragment|
      src_match = fragment.match(/src=["']([^"']+)["']/i)
      next unless src_match
      url = src_match[1]
      next if audio_url_hashes.values.any? { |v| v[:url] == url }
      sha_hash = Digest::SHA2.hexdigest(url)
      audio_url_hashes[sha_hash] = {url: url, extension: nil}
      line_copy.sub!(url, sha_hash) if replace
    end

    return [line, audio_url_hashes] if audio_url_hashes.empty?
    [line_copy, audio_url_hashes]
  end

  # Finds video URLs in a line: YouTube watch/short URLs and src= URLs with
  # known video file extensions. Replaces each URL with its SHA256 hash
  # placeholder and returns the modified line and a hash mapping each
  # placeholder to a {url:, extension:} hash. YouTube URLs use extension: nil
  # since the format cannot be determined from the URL alone.
  #
  # Lines containing the same URL twice (e.g. [URL](URL) markdown links)
  # produce only one hash entry; both occurrences are replaced.
  #
  # @param line [String]
  # @param replace [Boolean] whether to substitute URLs with hash placeholders
  # @return [Array(String, Hash)] modified line and {sha256 => {url:, extension:}} hash
  def self.extract_video_urls_from_line(line, replace = true)
    video_url_hashes = {}
    line_copy = line.dup

    # Pass 1: YouTube URLs — extension unknown until download
    line.scan(YOUTUBE_URL_REGEXP).each do |url|
      next if video_url_hashes.values.any? { |v| v[:url] == url }
      sha_hash = Digest::SHA2.hexdigest(url)
      video_url_hashes[sha_hash] = {url: url, extension: nil}
      line_copy.gsub!(url, sha_hash) if replace
    end

    # Pass 2: src= attributes with known video extensions
    line.to_enum(:scan, VIDEO_SRC_REGEXP).map { Regexp.last_match }.each do |md|
      url = md[2]
      next if video_url_hashes.values.any? { |v| v[:url] == url }
      sha_hash = Digest::SHA2.hexdigest(url)
      extension = File.extname(url.sub(/\?.*/, "").sub(/#.*$/, "")).downcase
      video_url_hashes[sha_hash] = {url: url, extension: extension}
      line_copy.gsub!(url, sha_hash) if replace
    end

    return [line, video_url_hashes] if video_url_hashes.empty?
    [line_copy, video_url_hashes]
  end

  # @param options [Hash] completely ignored
  # @raise [RuntimeError] if this archive doesn't have
  #        a mime-type of text/markdown
  def to_md(options = {})
    return string_data if mime_type == "text/markdown"
    raise "this archive doesn't have markdown content"
  end

  # @param minutes_ago: [Numeric] the number of minutes
  #        ago to test if this was created since.
  # @return true if the archive has a created_at
  #         that is on or after the specified number
  #         of minutes ago
  def created_since?(minutes_ago:)
    created_at >= minutes_ago.minutes.ago
  end

  # @return [Array] an Array of unique image URLs found in
  # the string_data of this Archive. They are in string format
  # and may not be valid.
  def image_urls
    return [] unless mime_type == "text/markdown"

    image_url_hashes = {}
    string_data.split(/\r\n|\n/).each do |line|
      _line, extracted_url_data = Archive.extract_image_links_from_line(line, false)
      next if extracted_url_data.empty?
      image_url_hashes.merge!(extracted_url_data)
    end
    image_url_hashes.values.pluck(:url)
  end

  def audio_urls
    return [] unless mime_type == "text/markdown"

    audio_url_hashes = {}
    string_data.split(/\r\n|\n/).each do |line|
      _line, extracted_url_data = Archive.extract_audio_urls_from_line(line, false)
      next if extracted_url_data.empty?
      audio_url_hashes.merge!(extracted_url_data)
    end
    audio_url_hashes.values.pluck(:url)
  end

  def video_urls
    return [] unless mime_type == "text/markdown"

    video_url_hashes = {}
    string_data.split(/\r\n|\n/).each do |line|
      _line, extracted_url_data = Archive.extract_video_urls_from_line(line, false)
      next if extracted_url_data.empty?
      video_url_hashes.merge!(extracted_url_data)
    end
    video_url_hashes.values.pluck(:url)
  end

  def media_urls
    media_url_hashes = {}
    string_data.split(/\r\n|\n/).each do |line|
      _line, extracted_url_data = Archive.extract_audio_urls_from_line(line, false)
      media_url_hashes.merge!(extracted_url_data) unless extracted_url_data.empty?
      _line, extracted_url_data = Archive.extract_video_urls_from_line(line, false)
      media_url_hashes.merge!(extracted_url_data) unless extracted_url_data.empty?
    end
    media_url_hashes.values.pluck(:url)
  end

  # Builds a new MediaObject in-memory and appends it to this archive's media_objects.
  # For audio, derives mime_type from the file extension.
  # For video, mime_type is nil (type is determined later) and hero_image_path is inherited.
  #
  # @param url [String] local archive path or remote URL
  # @param simple_type [String] "audio" or "video"
  # @return [MediaObject]
  def add_media_object(url, simple_type:)
    mime = (simple_type == "audio") ? Rack::Mime.mime_type(File.extname(url).downcase, nil) : nil
    # NOTE: the after_create on the MediaObject will schedule a transcription job
    media_objects.build(
      url: url,
      simple_type: simple_type,
      mime_type: mime,
      hero_image_path: (simple_type == "video") ? hero_image_path : nil
    )
  end
end
