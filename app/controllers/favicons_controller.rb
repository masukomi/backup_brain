class FaviconsController < ApplicationController
  include BackupBrain::Favicons
  MISSING_FAVICON_PATH = "/images/icons/website.svg"

  skip_before_action :set_user_count

  def get_favicon
    domain = sanitize_domain(params[:domain_name])
    return redirect_to(BackupBrain::Favicons::MISSING_FAVICON_PATH) if domain.blank?

    cached = find_cached_favicon(domain)

    if cached
      send_file cached, disposition: "inline"
    elsif (new_cached = fetch_and_cache_favicon(domain))
      send_file new_cached.to_s, disposition: "inline"
    else
      redirect_to BackupBrain::Favicons::MISSING_FAVICON_PATH
    end
  end

  private

  def sanitize_domain(raw)
    return "" if raw.blank?
    raw.to_s.downcase.gsub(/[^a-z0-9.\-]/, "").presence
  end
end
