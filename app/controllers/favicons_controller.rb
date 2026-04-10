class FaviconsController < ApplicationController
  GOOGLE_FAVICON_URL = "https://www.google.com/s2/favicons"
  FAVICON_CACHE_DIR  = Rails.public_path.join("images/favicons")
  MISSING_IMAGE_PATH = "/images/icons/missing_image_image.svg"

  skip_before_action :set_user_count

  def get_favicon
    domain = sanitize_domain(params[:domain_name])
    return redirect_to(MISSING_IMAGE_PATH) if domain.blank?

    cached = find_cached_favicon(domain)
    if cached
      send_file cached, disposition: "inline"
    else
      fetch_and_cache_favicon(domain)
    end
  end

  private

  def sanitize_domain(raw)
    return "" if raw.blank?
    raw.to_s.downcase.gsub(/[^a-z0-9.\-]/, "").presence
  end

  def find_cached_favicon(domain)
    Dir.glob(FAVICON_CACHE_DIR.join("#{domain_to_stem(domain)}.*")).first
  end

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
    send_file dest_path.to_s, disposition: "inline"
  rescue => e
    Rails.logger.error "[FaviconsController] Failed to fetch favicon for '#{domain}': #{e.message}"
    redirect_to MISSING_IMAGE_PATH
  end

  def domain_to_stem(domain)
    domain.gsub(".", "_")
  end
end
