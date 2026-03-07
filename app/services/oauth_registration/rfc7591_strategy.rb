require "oauth2"

module OauthRegistration
  class Rfc7591Strategy
    def initialize(base_url:, callback_url:, local_url:, site_type:)
      @base_url     = base_url
      @callback_url = callback_url
      @local_url    = local_url
      @site_type    = site_type
    end

    # Returns a symbolized hash with :client_id, :client_secret,
    # :client_secret_expires_at as described in RFC 7591.
    def register!
      registration_uri = discover_registration_uri

      payload = {
        application_type: "web",
        client_name: "BackupBrain",
        logo_uri: "#{@local_url}/images/icons/logo_180x180.png",
        redirect_uris: [@callback_url],
        grant_types: ["authorization_code"],
        response_types: ["code"],
        token_endpoint_auth_method: "client_secret_basic",
        scope: @site_type.default_scopes.join(" ")
      }

      http             = Net::HTTP.new(registration_uri.host, registration_uri.port)
      http.use_ssl     = registration_uri.scheme == "https"
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request                 = Net::HTTP::Post.new(registration_uri)
      request["Content-Type"] = "application/json"
      request.body            = payload.to_json

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

    private

    def discover_registration_uri
      discovery_uri = URI.join(@base_url, ".well-known/openid-configuration")
      resp = Net::HTTP.get_response(discovery_uri)

      if resp.is_a?(Net::HTTPSuccess)
        discovery = JSON.parse(resp.body)
        return URI.parse(discovery["registration_endpoint"]) if discovery["registration_endpoint"]
      end

      URI.join(@base_url, "/oauth2/register")
    rescue => e
      Rails.logger.warn "Discovery endpoint missing or unreachable: #{e.message}"
      URI.join(@base_url, "/oauth2/register")
    end
  end
end
