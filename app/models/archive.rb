class Archive
  SIMPLE_MD_LINK_REGEXP = /(?<!!)(\[(.*?)\]\((.*?)\))/i
  IMAGE_MD_LINK_REGEXP = /((!\[.*?\])\(\s*?(.*?)\s*?\))/i

  include Mongoid::Document
  include Mongoid::Timestamps
  field :mime_type,   type: String
  field :string_data, type: String

  embedded_in :bookmark

  # extracts all the image links
  # - fully qualifies the URLs
  # - replaces them with a sha256 hash
  # - returns a hash where the keys are the sha256 hashes
  #   and the values are the md links to the potentially archived images
  #
  # @example
  #
  # my [![](foo.jpg)](/link/to/something) favorite [links](/links)
  # becomes
  # my [abc123](/link/to/something) favorite [links](/links)
  # and the hash
  # {"abc123" => "![](foo.jpg)}
  #
  def self.extract_image_links_from_line(line, replace = true)
    match_datas = line
      .to_enum(:scan, Archive::IMAGE_MD_LINK_REGEXP)
      .map { Regexp.last_match }
    # ex. [#<MatchData "![](/bar.jpg)" 1:"![](/bar.jpg)" 2:"![]" 3:"/bar.jpg">,
    #      #<MatchData "![](/beeb.png)" 1:"![](/beeb.png)" 2:"![]" 3:"/beeb.png">]

    image_url_hashes = {}

    return [line, image_url_hashes] if match_datas.size == 0

    line_copy = line.dup
    match_datas.each_with_index do |md, index|
      url = md[3]
      sha_hash = Digest::SHA2.hexdigest(url)
      image_url_hashes[sha_hash] = url
      line_copy.sub!(md[1], sha_hash) if replace
    end
    [line_copy, image_url_hashes]
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
      _line, line_hash = Archive.extract_image_links_from_line(line, false)
      next if line_hash.empty?
      image_url_hashes.merge!(line_hash)
    end
    image_url_hashes.values
  end
end
