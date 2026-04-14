class Person
  # NOTE: People don't have a private flag because
  # they should never be visible to visitors who aren't logged in.

  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  include Search::InstanceMethods
  include BackupBrain::EmojiHelper
  include BackupBrain::Domains

  CLASS_PREFIXED_SEARCH_IDS = true
  SEARCHABLE_ATTRIBUTES     = %w[name description]
  SEARCH_INDEX_NAME         = "backup_brain_people"
  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:description]

  field :name,         type: String
  field :description,  type: String
  field :aliases,     type: Array,   default: []
  field :pronouns,    type: String
  field :avatar_image_path, type: String # path to avatar image
  # typically /archives/people/<id>/avatar.<extension>
  field :home_url,    type: String # URL of their home page
  field :domains,     type: Array

  has_many :social_media_accounts, dependent: :destroy
  has_and_belongs_to_many :bookmarks # NEVER DEPENDENT DESTROY

  validates :name, presence: true
  validate  :validate_domains
  before_save :emojify_default_fields, :guarantee_home_url_domain, :clean_domains!
  before_create :find_associated_bookmarks

  # enabled?() is controlled by the SEARCH_ENABLED environment variable
  if Search::Client.instance.enabled?
    after_create  :add_to_search
    after_update  :update_in_search
    after_destroy :remove_from_search
  end

  # @param profile_url [String] the canonical url of the user's profile.
  # @return [Person|nil] The first person with a social media account
  # matching the given profile_url
  def self.find_by_social_media_profile_url(profile_url)
    return nil if profile_url.blank?
    SocialMediaAccount.where(profile_url: /\A#{Regexp.escape(profile_url)}\z/i).first&.person
  end

  # BEGIN HOOKS
  # guarantees that the domain of home_url (if present) is
  # included in the list of domains
  def guarantee_home_url_domain
    if home_url
      domains ||= []
      home_url_domain = begin
        PublicSuffix.domain(URI.parse(home_url).host)&.downcase
      rescue
        nil
      end
      if home_url_domain.present? && domains.exclude?(home_url_domain)
        domains << home_url_domain
      end
    end
  end

  def find_associated_bookmarks
    return if domains.blank?
    self.bookmarks |= Bookmark.in(domain: domains).to_a
  end
end
