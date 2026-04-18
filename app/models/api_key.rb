class ApiKey
  include Mongoid::Document
  include Mongoid::Timestamps

  PERMISSIONABLE_MODELS = [
    Bookmark, DomainTrigger, Note, OauthSite, OauthSiteType,
    Person, Setting, SocialMediaAccount, Tag, Transcription, User
  ].freeze

  field :name,            type: String
  field :key,             type: String
  field :expiration_date, type: Date
  field :permissions,     type: Array, default: []

  validates :name, presence: true

  before_create :generate_key

  def self.is_valid?(key_string)
    record = where(key: key_string).first
    return false unless record
    !record.expired?
  end

  def expired?
    expiration_date.present? && expiration_date < Time.zone.today
  end

  private

  def generate_key
    self.key = SecureRandom.hex(32)
  end
end
