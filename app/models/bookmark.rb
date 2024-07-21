class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
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

  # splits a string of tags, downcases them,
  # replaces spaces with underscores, and returns an array
  def self.split_tags(tags)
    return [] if tags.blank?
    tags.strip.split(/,?\s+/).map { |t| t.strip.downcase.gsub(/\s+/, "_") }
  end

  def self.tagged_with(tag)
    where(:tags.in => [tag])
  end

  def self.tagged_with_any(tags)
    where(:tags.in => tags)
  end

  def self.tagged_with_all(tags)
    tags = tags.map { |tag| /#{tag}/ }
    where(:tags.all => tags)
  end

  def self.to_read
    where(to_read: true)
  end

  def self.not_to_read
    where(to_read: false)
  end

  def self.public
    where(private: false)
  end

  def self.private
    where(private: true)
  end

  def self.searchable
    where(private: false)
  end

  def self.searchable_with_user(user)
    where(user_id: user.id, private: false)
  end

  def self.searchable_with_user_and_tags(user, tags)
    where(:user_id => user.id, :private => false, :tags.all => tags)
  end

  def self.searchable_with_tags(tags)
    where(:private => false, :tags.all => tags)
  end

  def self.searchable_with_user_and_title(user, title)
    where(user_id: user.id, private: false, title: /#{title}/i)
  end

  def self.searchable_with_user_and_description(user, description)
    where(user_id: user.id, private: false, description: /#{description}/i)
  end

  def self.searchable_with_user_and_url(user, url)
    where(user_id: user.id, private: false, url: /#{url}/i)
  end

  def self.searchable_with_user_and_domain(user, domain)
    where(user_id: user.id, private: false, domain: /#{domain}/i)
  end

  def self.searchable_with_user_and_tags_and_title(user, tags, title)
    where(:user_id => user.id, :private => false, :tags.all => tags, :title => /#{title}/i)
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
    archives.min { |a| a.created_at }.string_data
  end
end
