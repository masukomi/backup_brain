module OauthRegistration
  # IndieAuth registration strategy for servers that use public client OAuth2
  # (no client_secret). Per IndieAuth spec, client_id must be a publicly reachable
  # URL whose document lists the allowed redirect_uri(s). We use the URL stored in
  # the indieauth_client_id_url setting (defaults to https://backupbrain.app) so
  # Misskey servers can always fetch it regardless of whether the user's BackupBrain
  # instance is publicly reachable. A static relay page at relay_url bounces the
  # browser back to the local instance after Misskey redirects.
  class IndieAuthStrategy
    def self.client_id
      begin
        return Setting.get_value_of_key("indieauth_client_id_urls").fetch("base_url")
      rescue BackupBrain::Errors::UnknownSetting
        Rails.logger.warn("indieauth_client_id_relay doesn't exist")
      rescue KeyError
        Rails.logger.warn("indieauth_client_id_relay doesn't have base_url defined")
      end
      "https://backupbrain.app"
    end

    def self.relay_url
      begin
        return Setting.get_value_of_key("indieauth_client_id_urls").fetch("relay_url")
      rescue BackupBrain::Errors::UnknownSetting
        Rails.logger.warn("indieauth_client_id_relay doesn't exist")
      rescue KeyError
        Rails.logger.warn("indieauth_client_id_relay doesn't have the relay_uri defined")
      end
      "#{client_id}/indieauth-callback"
    end

    def initialize(base_url:, callback_url:, local_url:, site_type:)
    end

    def register!
      {
        client_id: self.class.client_id,
        client_secret: nil,
        client_secret_expires_at: 0
      }
    end
  end
end
