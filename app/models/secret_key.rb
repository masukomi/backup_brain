class SecretKey
  include Mongoid::Document
  include Mongoid::Timestamps

  VALID_PERMISSIONS = %w[private_records].freeze

  field :name,        type: String
  field :key,         type: String
  field :permissions, type: Array, default: []

  validates :name, presence: true

  before_create :generate_key

  def self.is_valid?(key_string)
    exists?(key: key_string)
  end

  private

  def generate_key
    self.key = SecureRandom.hex(32)
  end
end
