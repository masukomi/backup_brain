require "nokogiri"

module BackupBrain
  # Extracts a hero image URL from an HTML string by checking common
  # metadata patterns in priority order.
  module Favicons
    GOOGLE_FAVICON_URL = "https://www.google.com/s2/favicons"
    FAVICON_CACHE_DIR  = Rails.public_path.join("images/favicons")
    MISSING_IMAGE_PATH = "/images/icons/missing_image_image.svg"

    # @param [String] domain like example.com
    # @returns [String|NillClass] servable path to image
    #                             E.g. /images/favicons/foo_com.png
    def cached_or_fetched_path(domain)
      path = find_cached_favicon(domain)
      return path if path
      fetch_and_cache_favicon(domain)
    end
    module_function :cached_or_fetched_path

    # @param [String] domain like example.com
    # @return [String|NillClass] servable path to image
    #                             E.g. /images/favicons/foo_com.png
    def find_cached_favicon(domain)
      absolute_path = Dir.glob(FAVICON_CACHE_DIR.join("#{domain_to_stem(domain)}.*")).first
      return nil unless absolute_path
      strip_rails_root_public(absolute_path)
    end
    module_function :find_cached_favicon

    # @param [String] domain like example.com
    # @return [String] downcased & periods replaced with underscores
    #                  E.g. Foo.com → foo_com
    def domain_to_stem(domain)
      domain.downcase.gsub(".", "_")
    end
    module_function :domain_to_stem

    def fetch_and_cache_favicon(domain)
      response = HTTParty.get(
        GOOGLE_FAVICON_URL,
        query: {sz: 64, domain: domain},
        follow_redirects: true,
        timeout: 10
      )
      raise "HTTP #{response.code}" unless response.success?

      content_type = response.headers["content-type"].to_s.split(";").first.strip.downcase
      ext          = Rack::Mime::MIME_TYPES.invert[content_type] || ".png"
      dest_path    = FAVICON_CACHE_DIR.join("#{domain_to_stem(domain)}#{ext}")

      File.binwrite(dest_path, response.body)
      strip_rails_root_public(dest_path)
    rescue => e
      Rails.logger.error "[FaviconsController] Failed to fetch favicon for '#{domain}': #{e.message}"
      nil
    end

    module_function :fetch_and_cache_favicon

    def strip_rails_root_public(absolute_path)
      chop_length = Rails.root.to_s.length + 7 # 7 for "/public"
      absolute_path[chop_length..]
    end
  end
end
