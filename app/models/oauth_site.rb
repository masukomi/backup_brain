class OauthSite
  include Mongoid::Document
  include Mongoid::Timestamps

  # remote server info
  field :base_url,                  type: String  # ex https://mastodon.social
  field :client_id,                 type: String
  field :client_secret,             type: String
  # client_secret_expires_at is the number of seconds since the epoch in UTC
  field :client_secret_expires_at,  type: Integer
  # registered_url is the url we registered with the remote server.
  # It is the url of THIS webapp. E.g. https://localhost:3334 or https://my.backupbrain.example.com
  # In a normal app with a non-volatile domain name this wouldn't be needed.
  field :registered_url,            type: String

  # User's oauth tokens
  field :access_token,              type: String
  field :access_token_expires_at,   type: Integer

  belongs_to :oauth_site_type, optional: true

  # validations
  validates :base_url, presence: true, uniqueness: true

  before_save :clean_base_url

  def expired_secret?
    return true if client_secret_expires_at.nil?
    return false if client_secret_expires_at == 0 # never expires
    client_secret_expires_at < Time.now.utc.to_i
  end

  protected

  def clean_base_url
    self.base_url = base_url.downcase.chomp("/")
  end
end
