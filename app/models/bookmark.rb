class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  include Search::InstanceMethods
  include BackupBrain::EmojiHelper

  CLASS_PREFIXED_SEARCH_IDS  = true
  SEARCHABLE_ATTRIBUTE_NAMES = %w[title url description tags created_at updated_at]
  SEARCH_INDEX_NAME          = "backup_brain_general"

  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:description, :title]

  field :title,       type: String
  field :url,         type: String
  field :description, type: String
  field :tags,        type: Array
  field :private,     type: Boolean, default: false
  field :to_read,     type: Boolean, default: false

  embeds_many :archives

  validates :title, presence: true
  validates :url, presence: true
  validates :url, uniqueness: true

  before_save  :emojify_default_fields
  after_create :generate_archive

  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end

  def has_archive?
    archives.present?
  end

  def sorted_archives
    archives.order_by(created_at: -1)
  end

  def latest_archive(mime_type = nil)
    return nil unless has_archive?
    return sorted_archives.first if mime_type.nil?
    sorted_archives.where(mime_type: mime_type).first
  end

  def generate_archive
    if url.blank?
      # only a warning because this shouldn't be a surprise.
      Rails.logger.warning(t("errors.bookmarks.cant_archive_without_url"))
      return
    end
    ArchiveUrlJob.perform_now(self)
  end
end
