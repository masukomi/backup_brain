class Note
  # NOTE: People don't have a private flag because
  # they should never be visible to visitors who aren't logged in.

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  extend BackupBrain::Taggable::ClassMethods
  include BackupBrain::Taggable::InstanceMethods
  include Search::InstanceMethods
  include BackupBrain::EmojiHelper
  include BackupBrain::Domains

  CLASS_PREFIXED_SEARCH_IDS = false
  SEARCHABLE_ATTRIBUTES     = %w[string_data tags]
  SEARCH_INDEX_NAME         = "backup_brain_notes"
  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:string_data]

  field :mime_type,   type: String, default: "text/markdown"
  field :string_data, type: String
  field :private,      type: Boolean, default: true
  field :tags,        type: Array,   default: []

  before_save    :clean_tags!, :clean_orphaned_tags

  before_destroy :clean_orphaned_tags
  after_save     :update_central_tags_list

  validates :string_data, :mime_type, :private, presence: true

  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end
end
