module OauthRegistration
  # IndieAuth registration strategy for servers that use public client OAuth2
  # (no client_secret). Per IndieAuth spec, client_id must be a publicly reachable
  # URL whose document lists the allowed redirect_uri(s). We use backupbrain.app as
  # client_id so that Misskey servers can always fetch it regardless of whether the
  # user's BackupBrain instance is publicly reachable. A static relay page at
  # RELAY_URL bounces the browser back to the local instance after Misskey redirects.
  class IndieAuthStrategy
    CLIENT_ID = ENV.fetch("INDIE_AUTH_CLIENT_ID", "https://backupbrain.app").freeze
    RELAY_URL = ENV.fetch("INDIE_AUTH_RELAY_URL", "https://backupbrain.app/misskey-callback").freeze

    def initialize(base_url:, callback_url:, local_url:, site_type:)
    end

    def register!
      {
        client_id: CLIENT_ID,
        client_secret: nil,
        client_secret_expires_at: 0
      }
    end
  end
end
