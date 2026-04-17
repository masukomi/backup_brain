require "oauth2"

class RemoteCredentialsController < ApplicationController
  def index
    @site_types = OauthSiteType.all.order_by(name: :asc)
    @sites_by_type = OauthSite.all.group_by(&:oauth_site_type)
  end

  def destroy
    OauthSite.find(params[:id]).destroy
    redirect_to remote_credentials_path
  end

  # The user has entered a domain name, chosen a site type, and clicked "Connect".
  def begin_auth
    base_url = params[:base_url].to_s.downcase.strip.chomp("/")
    base_url = "https://#{base_url}" unless base_url.start_with?("http")

    site_type = OauthSiteType.find(params[:site_type_id])

    # because this is a self-hosted app we can't rely on the current domain / callback url
    # remaining stable. The user may have changed it since the last time they connected.
    current_local_url = local_url

    oauth_site = OauthSite.where(base_url: base_url, registered_url: current_local_url).first

    if oauth_site&.expired_secret?
      result = strategy_for(base_url, site_type).register!
      oauth_site.update!(
        client_id: result[:client_id],
        client_secret: result[:client_secret],
        client_secret_expires_at: result[:client_secret_expires_at]
      )
    end

    unless oauth_site
      # it's possible we have old data where we registered but then changed
      # the local_url via .env or something. Purge the old credentials.
      if OauthSite.where(base_url: base_url).count > 0
        OauthSite.where(base_url: base_url).delete_all
      end
      result = strategy_for(base_url, site_type).register!
      oauth_site = OauthSite.create!(
        base_url: base_url,
        registered_url: current_local_url,
        oauth_site_type: site_type,
        client_id: result[:client_id],
        client_secret: result[:client_secret],
        client_secret_expires_at: result[:client_secret_expires_at]
      )
    end

    raise OAuth2::Error.new(nil, I18n.t("oauth2.errors.registration_failed")) unless oauth_site

    client = OAuth2::Client.new(
      oauth_site.client_id,
      oauth_site.client_secret,
      site: base_url,
      authorize_url: site_type.authorization_path,
      token_url: site_type.token_path
    )

    pkce_params = {}
    if site_type.requires_pkce
      code_verifier = SecureRandom.urlsafe_base64(96)
      code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
      session["pkce_#{oauth_site._id}"] = code_verifier
      pkce_params = {code_challenge: code_challenge, code_challenge_method: "S256"}
    end

    effective_redirect_uri = site_type.requires_pkce ?
      OauthRegistration::IndieAuthStrategy::RELAY_URL : callback_url
    effective_state = if site_type.requires_pkce
      Base64.strict_encode64(JSON.generate(id: oauth_site._id.to_s, u: local_url))
    else
      oauth_site._id.to_s
    end

    redirect_to client.auth_code.authorize_url(
      redirect_uri: effective_redirect_uri,
      state: effective_state,
      scope: site_type.default_scopes.join(" "),
      **pkce_params
    ), allow_other_host: true
  end

  # The user has authenticated on the remote server and been redirected back here.
  # We exchange the authorization code for an access token.
  def callback
    unless params[:code].present? && params[:state].present?
      raise OAuth2::Error.new(nil, I18n.t("oauth2.errors.unexpected_response",
        response: params.to_json,
        expected: "code & state parameters"))
    end

    site_id = begin
      decoded = JSON.parse(Base64.decode64(params[:state]))
      decoded["id"]
    rescue
      params[:state]
    end
    oauth_site = OauthSite.where(_id: site_id).first
    raise OAuth2::Error.new(nil, I18n.t("oauth2.errors.state_failure")) unless oauth_site

    site_type = oauth_site.oauth_site_type

    client = OAuth2::Client.new(
      oauth_site.client_id,
      oauth_site.client_secret,
      auth_scheme: :request_body,
      token_url: site_type.token_path,
      site: oauth_site.base_url
    )

    begin
      token_params = {
        redirect_uri: site_type.requires_pkce ?
          OauthRegistration::IndieAuthStrategy::RELAY_URL : callback_url
      }
      if site_type.requires_pkce
        code_verifier = session.delete("pkce_#{oauth_site._id}")
        token_params[:code_verifier] = code_verifier if code_verifier.present?
      end

      oauth2_access_token = client.auth_code.get_token(params[:code], **token_params)

      oauth_site.access_token = oauth2_access_token.token
      oauth_site.access_token_expires_at = oauth2_access_token.expires_at
      oauth_site.save!

      redirect_to root_path, notice: I18n.t("oauth2.successes.account_linked")
    rescue OAuth2::Error => e
      Rails.logger.error "OAuth2 callback failed: #{e.message}"
      redirect_to root_path, alert: I18n.t("oauth2.errors.connection_failure", domain: oauth_site.base_url)
    end
  end

  private

  def local_url
    host_name = ENV.fetch("HOST_NAME")
    host_uses_ssl = ENV.fetch("HOST_USES_SSH", "false") == "true"
    return "https://#{host_name}" if host_uses_ssl
    port = ENV.fetch("PORT")
    "http://#{host_name}:#{port}"
  end

  def callback_url
    "#{local_url}/remote_authorizations/callback"
  end

  def strategy_for(base_url, site_type)
    klass = OauthSiteType.strategy_class_for(site_type.registration_strategy)
    klass.new(
      base_url: base_url,
      callback_url: callback_url,
      local_url: local_url,
      site_type: site_type
    )
  end
end
