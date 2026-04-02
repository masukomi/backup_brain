class Setting
  include Mongoid::Document
  include Mongoid::Timestamps

  # NOTE: There was a really good reason why value is a hash with a value key.
  # However, I wrote it years ago, for another app, and
  # I just don't remember what it was. 😿

  VALID_VALUE_TYPES = %i[boolean integer string array hash].freeze

  field :lookup_key,  type:    String
  field :summary,     type:    String
  field :description, type:    String
  field :value,       type:    Hash
  field :value_type,  default: :boolean
  field :visible,     type:    Boolean, default: false

  embeds_many :setting_dependencies, cascade_callbacks: true

  before_save :guarantee_value_default, :dependency_settings_presence
  after_save :bust_cache
  validates :lookup_key, :summary, :description, presence: true
  validates :lookup_key, uniqueness: true
  validate :valid_value
  validates :value_type,
    inclusion: {in: VALID_VALUE_TYPES,
                message: "value_type must be one of: #{VALID_VALUE_TYPES.join(", ")}"}

  def self.cached_values
    @cached_values ||= Setting.all.each_with_object({}) do |s, hash|
      hash[s.lookup_key] = s.value
    end
  end

  def self.get_value_of_key(lookup_key)
    cache = cached_values
    unless cache.key?(lookup_key)
      raise BackupBrain::Errors::UnknownSetting.new(
        "No setting found with lookup_key: #{lookup_key}"
      )
    end
    value_hash = cache[lookup_key]
    value_hash.nil? ? nil : value_hash[:value]
  end

  def inner_value
    value.nil? ? nil : value[:value]
  end

  def is_boolean?
    value_type == :boolean && is_value_bool?
  end

  def is_value_bool?
    val = inner_value
    # ugh. so surprised there isn't a BoolClass in ruby
    val.is_a?(TrueClass) || val.is_a?(FalseClass)
  end

  private

  def bust_cache
    self.class.instance_variable_set(:@cached_values, nil)
  end

  def guarantee_value_default
    return if value.present? && value.is_a?(Hash) && value.has_key?(:value)
    self.value = {value: nil}
  end

  def dependency_settings_presence
    missing_dependency_settings = []
    setting_dependencies.each do |sd|
      missing_dependency_settings << sd.dependency_lookup_key
    end
    if missing_dependency_settings.present?
      errors.add(:setting_dependencies, "the following dependency settings are missing: #{missing_dependency_settings.join(", ")}")
    end
  end

  def valid_value
    if (value_type == :boolean) && !is_value_bool?
      errors.add(:value, "must be a boolean is a #{inner_value.class.name}")
    end
    if (value_type == :integer) && !inner_value.is_a?(Integer)
      errors.add(:value, "must be an integer is a #{inner_value.class.name}")
    end
    if (value_type == :string) && !inner_value.is_a?(String)
      errors.add(:value, "must be a string is a #{inner_value.class.name}")
    end
    if (value_type == :array) && !inner_value.is_a?(Array)
      errors.add(:value, "must be an array is a #{inner_value.class.name}")
    end
    if (value_type == :hash) && !inner_value.is_a?(Hash)
      errors.add(:value, "must be a hash is a #{inner_value.class.name}")
    end

    # phew. Ok now let's test dependencies
    setting_dependencies.each do |dep|
      messages = []
      unless dep.dependable?
        messages << dep.failure_message
      end
      if messages.present?
        errors.add(:value, messages.join("\n"))
      end
    end
  end
end
