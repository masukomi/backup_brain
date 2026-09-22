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

  index({key: 1}, {unique: true})

  validates :name, presence: true

  before_create :generate_key

  # Returns the ApiKey matching key_string, or nil if there's no such
  # key or it has expired.
  #
  # @param [String] key_string - the key presented by the requester
  # @return [ApiKey, nil]
  def self.authenticate(key_string)
    return nil if key_string.blank?
    record = where(key: key_string).first
    return nil unless record
    return nil unless ActiveSupport::SecurityUtils.secure_compare(record.key.to_s, key_string)
    return nil if record.expired?
    record
  end

  def self.is_valid?(key_string)
    authenticate(key_string).present?
  end

  def expired?
    expiration_date.present? && expiration_date < Time.zone.today
  end

  # @param [String] action - "read" or "write"
  # @param [Class] klass - a model class, e.g. Bookmark
  def permits?(action, klass)
    permissions.include?("#{action}:#{BackupBrain::ModelPaths.path_string(klass)}")
  end

  private

  def generate_key
    self.key = SecureRandom.hex(32)
  end
end
