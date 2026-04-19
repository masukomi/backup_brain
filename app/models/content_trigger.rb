class ContentTrigger
  include Mongoid::Document
  include Mongoid::Timestamps

  include BackupBrain::Triggers
  include BackupBrain::Taggable::InstanceMethods

  field :name,              type:    String
  field :simple_triggers,   type:    Array,   default: []
  field :case_insensitive,  type:    Boolean, default: true
  field :mark_as_private,   type:    Boolean, default: false
  field :mark_to_read,      type:    Boolean, default: false
  field :mark_as_sensitive, type:    Boolean, default: false
  field :tags,              type:    Array,   default: []

  before_save :clean_tags!
  validates :name, presence: true, uniqueness: true
  after_save :bust_cache

  SUPPORTED_OBJECT_TYPES = [Bookmark, Archive, Note].freeze

  # applies all applicable ContentTrigger triggers
  def self.apply_triggers(mongoid_doc)
    unless SUPPORTED_OBJECT_TYPES.include?(mongoid_doc.class)
      raise BackupBrain::Errors::UnsupportedDocumentType.new("Don't know how to apply triggers to #{mongoid_doc.class}")
    end
    # presumes that the doc responds_to: :tags, :to_read, and :private
    return if cached_values.blank?

    applied = false
    cached_triggers.each do |trigger|
      next unless trigger.applies?(mongoid_doc)
      trigger.apply_to(mongoid_doc)
      applied = true
    end
    applied # don't want to return cached_values
  end

  # applies all applicable ContentTrigger triggers
  # and calls save! on the mongoid_doc
  def self.apply_triggers!(mongoid_doc)
    applied = apply_triggers(mongoid_doc)
    mongoid_doc.save! if applied
  end

  def self.cached_triggers
    @cached_triggers ||= ContentTrigger.all
  end

  def applies?(string_data)
    return false if simple_triggers.blank?
    return simple_triggers.flat_map { |word| string_data.scan(/#{word}/i) }.any? if case_insensitive
    simple_triggers.flat_map { |word| string_data.scan(/#{word}/) }.any?
  end

  private

  def bust_cache
    self.class.instance_variable_set(:@cached_triggers, nil)
  end
end
