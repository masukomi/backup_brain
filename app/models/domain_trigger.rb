class DomainTrigger
  include Mongoid::Document
  include Mongoid::Timestamps

  include BackupBrain::Domains
  include BackupBrain::Triggers
  include BackupBrain::Taggable::InstanceMethods

  field :domain,            type:    String
  field :mark_as_private,   type:    Boolean, default: false
  field :mark_as_sensitive, type:    Boolean, default: false
  field :mark_to_read,      type:    Boolean, default: false
  field :tags,              type:    Array,   default: []

  before_save :clean_tags!, :clean_domain!
  validates :domain, presence: true, uniqueness: true
  validate  :validate_domain
  after_save :bust_cache

  def self.trigger_for_domain(domain)
    cached_values[domain]
  end

  def self.cached_values
    @cached_values ||= DomainTrigger.all.index_by do |dt|
      dt.domain
    end
  end

  def clean_domain!
    return if domain.blank? # validations will handle errors about this
    clean_domain(domain).downcase
  end

  private

  def bust_cache
    self.class.instance_variable_set(:@cached_values, nil)
  end
end
