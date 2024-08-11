class Setting
  include Mongoid::Document
  include Mongoid::Timestamps

  VALID_VALUE_CLASSES = Set.new([TrueClass, FalseClass, Integer, String, Array, Hash]).freeze

  field :lookup_key,  type:    String
  field :summary,     type:    String
  field :description, type:    String
  field :value
  field :visible,     type:    Boolean, default: false

  validates :lookup_key, :summary, :description, presence: true
  validates :lookup_key, uniqueness: true
  validate :valid_value

  private

  def valid_value
    # ok, value.class gets converted to a BSON::Document
    # but it LOOKS like a normal Hash, or whatever, when you
    # inspect it. So, that's why this is so funky
    unless VALID_VALUE_CLASSES.any? { |klass| value.is_a?(klass) }
      errors.add(:value, I18n.t("settings.errors.unsupported_value_type", type: value.class.name))
    end
  end
end
