class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  extend BackupBrain::Taggable::ClassMethods
  include BackupBrain::Taggable::InstanceMethods
  include Search::InstanceMethods
  include BackupBrain::EmojiHelper

  CLASS_PREFIXED_SEARCH_IDS = true
  SEARCHABLE_ATTRIBUTES = %w[private title url description tags archives_text created_at updated_at]
  SEARCH_INDEX_NAME          = "backup_brain_general"

  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:description, :title]

  field :title,       type: String
  field :url,         type: String
  field :domain,      type: String
  field :description, type: String
  field :tags,        type: Array,   default: []
  field :private,     type: Boolean, default: false
  field :to_read,     type: Boolean, default: false

  embeds_many :archives
  embeds_many :failed_archive_attempts

  belongs_to :user

  validates :title, presence: true
  validates :url, presence: true
  validates :url, uniqueness: true

  before_save    :emojify_default_fields
  before_save    :set_domain
  before_save    :maybe_generate_archive
  before_save    :clean_orphaned_tags
  after_create   :generate_archive
  before_destroy :clean_orphaned_tags

  after_save     :update_central_tags_list

  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end

  def self.to_read
    where(to_read: true)
  end

  def self.not_to_read
    where(to_read: false)
  end

  # NOTE: you can't override self.public
  # because .public is the same as public
  # just like private and protected
  # so this gets a stupid name

  # @return Mongoid::Criteria for public bookmarks
  def self.public_bookmarks
    where(private: false)
  end

  # @return Mongoid::Criteria for private bookmarks
  def self.private_bookmarks
    where(private: true)
  end

  # @return Mongoid::Criteria for unarchived bookmarks
  def self.unarchived
    Bookmark.or({:archives.exists => false}, {archives: {"$size": 0}})
  end

  def is_fresh?
    created_at > 2.minutes.ago
  end

  # BEGIN HOOKS

  def set_domain
    return (self.domain = nil) if url.blank?
    self.domain = begin
      PublicSuffix.domain(URI.parse(url).host)
    rescue
      nil
    end
    # PublicSuffix uses the Public Suffix List:
    # https://publicsuffix.org/
    # to know that in "google.co.uk", "co.uk" is the domain suffix
    # but in "google.com", ".com" is the suffix.
    # calling .domain on it gets you the
    # domain without the subdomains.
    # eg myUsername.medium.com returns medium.com
  end

  # Generates a new archive asynchronously
  # if specific update criteria are met
  # currently:
  #  - if the url has changed
  def maybe_generate_archive
    generate_archive(false) if url_changed?
  end

  def clean_orphaned_tags
    if changed_attributes.keys.include?("tags")
      DeleteOrphanedTagsJob.perform_later
    end
  end

  # END HOOKS

  # BEGIN ARCHIVES
  def has_archive?
    archives.present?
  end

  def last_archive_attempt_failed?
    return false if failed_archive_attempts.blank?
    return true unless has_archive?
    if has_archive? && failed_archive_attempts.last.created_at > archives.last.created_at
      return true
    end
    false # can't happen. I think.
  end

  def sorted_archives
    archives.order_by(created_at: -1)
  end

  def latest_archive(mime_type = nil)
    return nil unless has_archive?
    return sorted_archives.first if mime_type.nil?
    sorted_archives.where(mime_type: mime_type).first
  end

  # Kicks off the ArchiveUrlJob which creates a text-only
  # archive of the page. By default this will run in the background
  # but some processes (like the cleanup task) need to know if it worked
  # or not.
  #
  # @param[Boolean] now - Determines if the job is run now, or asynchronously. Defaults to false (asynchronous).
  def generate_archive(now = false)
    # FIXME: this is hack until we can replace the "reader"
    # command line tool with a ruby library that actually works
    # https://github.com/masukomi/backup_brain/issues/55
    return unless ENV["I_INSTALLED_READER"] == "true"

    if url.blank?
      # only a warning because this shouldn't be a surprise.
      Rails.logger.warning(t("errors.bookmarks.cant_archive_without_url"))
      return false
    end
    if now
      ArchiveUrlWithoutRetriesJob.perform_now(bookmark_id: _id.to_s) # returns true / false
    else
      ArchiveUrlJob.perform_later(bookmark_id: _id.to_s)
      true
    end
  end

  def archives_text
    return nil unless has_archive?
    # NOTE: intentionally NOT searching the text of ALL the archives
    #      because Meilisearch has an artificial limitation of 65,535
    #      "positions" per attribute, and anything after that will
    #      be ignored. It's kinda, but not quote a count a words.
    #      If anyone chooses to create semi-regular archives we'll
    #      likely exceed that.
    #
    #      The documentation pages on search & archives will note this limitation.
    #      https://www.meilisearch.com/docs/learn/advanced/known_limitations#maximum-number-of-words-per-attribute
    archives.last.string_data
    # archives.max{ |a| a.created_at }.string_data
  end
  # BEGIN ARCHIVES
end
