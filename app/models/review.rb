class Review
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
  SEARCHABLE_ATTRIBUTES     = %w[title string_data tags]
  SEARCH_INDEX_NAME         = "backup_brain_reviews"
  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:string_data]

  # title is optional UNLESS sensitive is true.
  # We need something un-fuzzed to display
  field :title,       type: String
  field :string_data, type: String  # Markdown content of the review
  field :rating,      type: Float
  field :source_url,  type: String  # URL of the original remote review (for deduplication)
  field :private,     type: Boolean, default: true
  field :sensitive,   type: Boolean, default: false
  field :tags,        type: Array,   default: []
  field :image_path,  type: String
  # path to image representing thing being reviewed
  # typically /archives/social_media_accounts/<id>/avatar.<extension>

  before_save    :apply_content_triggers, :clean_tags!, :clean_orphaned_tags

  before_destroy :clean_orphaned_tags
  after_save     :update_central_tags_list

  validates :string_data, presence: true
  validates :private, inclusion: {in: [true, false]}
  validates :title, presence: true, if: :sensitive?

  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end

  def apply_content_triggers
    # string_data_changed? returns false on a new document where it's nil
    # returns true once you set it or if it's an existing document that's changed
    if string_data_changed?
      ContentTrigger.apply_triggers(test_string: string_data, apply_to: self)
    end
  end
end
