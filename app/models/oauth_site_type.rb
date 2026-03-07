class OauthSiteType
  include Mongoid::Document
  include Mongoid::Timestamps

  STRATEGIES = {
    "mastodon_v1_apps" => "OauthRegistration::MastodonStrategy",
    "rfc7591" => "OauthRegistration::Rfc7591Strategy"
  }.freeze

  field :name,                  type: String  # "Mastodon"
  field :slug,                  type: String  # "mastodon"
  field :description,           type: String
  field :registration_strategy, type: String  # "mastodon_v1_apps" | "rfc7591"
  field :registration_path,     type: String  # "/api/v1/apps"
  field :authorization_path,    type: String  # "/oauth/authorize"
  field :token_path,            type: String  # "/oauth/token"
  field :default_scopes,        type: Array, default: []  # ["read"]

  has_many :oauth_sites

  validates :name, :slug, :registration_strategy,
    :authorization_path, :token_path, presence: true
  validates :name, :slug, uniqueness: true

  def self.strategy_class_for(strategy_name)
    class_name = STRATEGIES[strategy_name]
    raise I18n.t("oauth2.errors.unknown_site_type") unless class_name
    class_name.constantize
  end
end
