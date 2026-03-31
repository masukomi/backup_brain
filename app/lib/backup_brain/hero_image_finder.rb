require "nokogiri"

module BackupBrain
  # Extracts a hero image URL from an HTML string by checking common
  # metadata patterns in priority order.
  module HeroImageFinder
    # Meta tag selectors tried in order. Returns the first non-blank content/href.
    SELECTORS = [
      # Open Graph
      ["meta[property='og:image']",         "content"],
      ["meta[name='og:image']",             "content"],
      # Twitter Cards
      ["meta[property='twitter:image']",    "content"],
      ["meta[name='twitter:image']",        "content"],
      ["meta[property='twitter:image:src']","content"],
      ["meta[name='twitter:image:src']",    "content"],
      # Schema.org / generic
      ["meta[itemprop='image']",            "content"],
      # Older rel=image_src link tag
      ["link[rel='image_src']",             "href"]
    ].freeze

    # Returns the hero image URL found in +html_string+, or nil if none.
    #
    # @param html_string [String] raw HTML
    # @return [String, nil]
    def self.find(html_string)
      return nil if html_string.blank?
      doc = Nokogiri::HTML(html_string)
      SELECTORS.each do |selector, attribute|
        node = doc.at_css(selector)
        next unless node
        value = node[attribute].to_s.strip
        return value unless value.empty?
      end
      nil
    end
  end
end
