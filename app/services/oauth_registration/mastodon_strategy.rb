require "oauth2"

module OauthRegistration
  class MastodonStrategy
    def initialize(base_url:, callback_url:, local_url:, site_type:)
      @base_url     = base_url
      @callback_url = callback_url
      @local_url    = local_url
      @site_type    = site_type
    end

    # Returns a symbolized hash with at least :client_id, :client_secret,
    # :client_secret_expires_at (0 = never expires, per Mastodon behaviour).
    def register!
      uri = URI.join(@base_url, @site_type.registration_path)

      payload = {
        client_name: "BackupBrain",
        redirect_uris: @callback_url,
        scopes: @site_type.default_scopes.join(" "),
        website: @local_url
      }

      http             = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request                  = Net::HTTP::Post.new(uri)
      request["Content-Type"]  = "application/json"
      request.body             = payload.to_json

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        json = JSON.parse(response.body, symbolize_names: true)
        {
          client_id: json[:client_id],
          client_secret: json[:client_secret],
          client_secret_expires_at: json[:client_secret_expires_at] || 0
        }
      else
        raise OAuth2::Error.new(response, I18n.t("oauth2.errors.registration_failed"))
      end
    end
  end
end
