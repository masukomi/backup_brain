module OauthRegistration
  # BookWyrm does not support dynamic client registration.
  # The user must create an OAuth application manually on their BookWyrm server
  # at /o/applications/register/ and supply the client_id here.
  # client_secret is optional — BookWyrm supports public OAuth2 clients.
  class BookwyrmStrategy
    def initialize(base_url:, callback_url:, local_url:, site_type:, client_id:, client_secret: nil, **)
      @client_id     = client_id
      @client_secret = client_secret
    end

    def register!
      raise ArgumentError, I18n.t("oauth2.errors.bookwyrm_client_id_required") if @client_id.blank?
      {
        client_id: @client_id,
        client_secret: @client_secret,
        client_secret_expires_at: 0
      }
    end
  end
end
