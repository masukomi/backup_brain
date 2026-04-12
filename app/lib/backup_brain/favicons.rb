require "nokogiri"

module BackupBrain
  # Extracts a hero image URL from an HTML string by checking common
  # metadata patterns in priority order.
  module Favicons
    GOOGLE_FAVICON_URL = "https://www.google.com/s2/favicons"
    FAVICON_CACHE_DIR  = Rails.public_path.join("images/favicons")
    MISSING_IMAGE_PATH = "/images/icons/missing_image_image.svg"

    def cached_or_fetched_path(domain)
      path = find_cached_favicon(domain)
      return path if path
      fetch_and_cache_favicon(domain)
    end
    module_function :cached_or_fetched_path

    def find_cached_favicon(domain)
      Dir.glob(FAVICON_CACHE_DIR.join("#{domain_to_stem(domain)}.*")).first
    end
    module_function :find_cached_favicon

    def domain_to_stem(domain)
      domain.gsub(".", "_")
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
      dest_path
    rescue => e
      Rails.logger.error "[FaviconsController] Failed to fetch favicon for '#{domain}': #{e.message}"
      nil
    end

    module_function :fetch_and_cache_favicon
  end
end
