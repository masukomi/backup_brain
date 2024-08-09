class Setting
  include Mongoid::Document
  include Mongoid::Timestamps

  VALID_VALUE_TYPES = %i[boolean integer string array hash].freeze

  field :lookup_key,  type:    String
  field :summary,     type:    String
  field :description, type:    String
  field :value,       type:    Hash
  field :value_type,                    default: :boolean
  field :visible,     type:    Boolean, default: false

  before_save :guarantee_value_default
  validates :lookup_key, :summary, :description, presence: true
  validates :lookup_key, uniqueness: true
  validate :valid_value
  validates :value_type,
    inclusion: {in: VALID_VALUE_TYPES,
                message: "value_type must be one of: #{VALID_VALUE_TYPES.join(", ")}"}

  def inner_value
    value.nil? ? nil : value[:value]
  end

  private

  def guarantee_value_default
    return if value.present? && value.is_a?(Hash) && value.has_key?(:value)
    self.value = {value: nil}
  end

  def valid_value
    if (value_type == :boolean) && !is_value_bool?
      errors.add(:value, "value must be a boolean")
    end
    if (value_type == :integer) && !inner_value.is_a?(Integer)
      errors.add(:value, "value must be an integer")
    end
    if (value_type == :string) && !inner_value.is_a?(String)
      errors.add(:value, "value must be a string")
    end
    if (value_type == :array) && !inner_value.is_a?(Array)
      errors.add(:value, "value must be an array")
    end
    if (value_type == :hash) && !inner_value.is_a?(Hash)
      errors.add(:value, "value must be a hash")
    end
  end

  def is_value_bool?
    val = inner_value
    # ugh. so surprised there isn't a BoolClass in ruby
    val.is_a?(TrueClass) || val.is_a?(FalseClass)
  end
end
