module OauthRegistration
  # IndieAuth registration strategy for servers that use public client OAuth2
  # (no client_secret). The client_id is the app's own URL, per IndieAuth spec.
  # Used by Misskey, which follows RFC 9110 / IndieAuth rather than RFC 7591.
  class IndieAuthStrategy
    def initialize(base_url:, callback_url:, local_url:, site_type:)
      @local_url = local_url
    end

    # Returns a hash matching the shape expected by RemoteCredentialsController:
    # client_id = local app URL, client_secret = nil (public client).
    def register!
      {
        client_id: @local_url,
        client_secret: nil,
        client_secret_expires_at: 0
      }
    end
  end
end
