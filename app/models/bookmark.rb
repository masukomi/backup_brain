class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  include Search::InstanceMethods
  include BackupBrain::EmojiHelper

  CLASS_PREFIXED_SEARCH_IDS = true
  SEARCHABLE_ATTRIBUTES = %w[title url description tags archives_text created_at updated_at]
  SEARCH_INDEX_NAME          = "backup_brain_general"

  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:description, :title]

  field :title,       type: String
  field :url,         type: String
  field :domain,      type: String
  field :description, type: String
  field :tags,        type: Array
  field :private,     type: Boolean, default: false
  field :to_read,     type: Boolean, default: false

  embeds_many :archives

  belongs_to :user

  validates :title, presence: true
  validates :url, presence: true
  validates :url, uniqueness: true

  before_save  :emojify_default_fields
  before_save  :set_domain
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

  # Kicks off the ArchiveUrlJob which creates a text-only
  # archive of the page. By default this will run in the background
  # but some processes (like the cleanup task) need to know if it worked
  # or not.
  #
  # @param[Boolean] now - Determines if the job is run now, or asynchronously. Defaults to false (asynchronous).
  def generate_archive(now = false)
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
    archives.map { |a| a.string_data }
  end
end
