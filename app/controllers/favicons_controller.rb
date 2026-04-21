class FaviconsController < ApplicationController
  include BackupBrain::Favicons
  MISSING_FAVICON_PATH = "/images/icons/website.svg"

  skip_before_action :set_user_count

  def get_favicon
    domain = sanitize_domain(params[:domain_name])
    return redirect_to(BackupBrain::Favicons::MISSING_FAVICON_PATH) if domain.blank?

    cached = cached_or_fetched_path(domain)

    redirect_to cached || BackupBrain::Favicons::MISSING_FAVICON_PATH
  end

  private

  def sanitize_domain(raw)
    return "" if raw.blank?
    raw.to_s.downcase.gsub(/[^a-z0-9.\-]/, "").presence
  end
end
