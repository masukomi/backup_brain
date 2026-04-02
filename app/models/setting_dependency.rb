class SettingDependency
  include Mongoid::Document
  include Mongoid::Timestamps

  VALID_VALUE_CLASSES = Set.new([TrueClass, FalseClass, Integer, String, Array, Hash]).freeze

  field :dependency_lookup_key,  type: String
  # A bit of ruby code that must return true
  field :test,        type: String
  field :name,        type: String
  field :notes,       type: String
  embedded_in :setting

  validates :dependency_lookup_key, :test, :name, :notes, presence: true

  def dependent_setting_exists?
    Setting.where(lookup_key: dependency_lookup_key).count > 0
  end
  def dependable?
    return false unless dependent_setting_exists?
    eval(test) == true
  end

  def failure_message
    "#{name} #{notes}"
  end
end
