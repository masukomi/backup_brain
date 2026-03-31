module BackupBrain
  module YouTube
    URL_REGEXP = /https?:\/\/(?:www\.|m\.)?(?:youtube\.com\/watch\?(?:[^\s)#]*&)*v=|youtu\.be\/)([\w-]+)[^\s)#]*/

    # @param url [String]
    # @return [String, nil] the YouTube video ID, or nil if the URL is not a YouTube URL
    def self.video_id(url)
      url.to_s.match(URL_REGEXP)&.captures&.first
    end

    # @param url [String]
    # @return [String, nil] the YouTube embed src URL (with ?start=N if a timestamp is present), or nil
    def self.embed_url(url)
      id = video_id(url)
      return nil unless id
      timestamp = url.to_s.match(/[?&]t=(\d+)s?/)&.captures&.first
      src = "https://www.youtube.com/embed/#{id}"
      src += "?start=#{timestamp}" if timestamp
      src
    end

    # @param url [String] the original YouTube URL (used to extract video ID and timestamp)
    # @return [String, nil] a YouTube iframe embed HTML string, or nil
    def self.embed_html(url)
      src = embed_url(url)
      return nil unless src
      %(<iframe width="560" height="315" src="#{src}" frameborder="0" allowfullscreen></iframe>)
    end
  end
end
