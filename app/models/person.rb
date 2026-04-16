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
  include BackupBrain::ArchiveTools

  CLASS_PREFIXED_SEARCH_IDS = true
  SEARCHABLE_ATTRIBUTES     = %w[name description]
  SEARCH_INDEX_NAME         = "backup_brain_people"
  # Fields where it'll look for Slack-style emoji aliases
  EMOJIFIABLE_FIELDS = [:description]
  MISSING_AVATAR_PATH = "/images/icons/missing_avatar.svg"

  field :name,        type: String
  field :description, type: String
  field :aliases,     type: Array,   default: []
  field :pronouns,    type: String
  field :avatar_image_path, type: String # path to avatar image
  # typically /archives/people/<id>/avatar.<extension>
  field :home_url,    type: String # URL of their home page
  field :domains,     type: Array
  field :email,       type: String

  has_many :social_media_accounts, dependent: :destroy
  has_and_belongs_to_many :bookmarks # NEVER DEPENDENT DESTROY

  validates :name, presence: true
  validates :email, :allow_blank, format: {with: /\A([^@\s]+)@((?:[-a-z0-9]+\.)+[a-z]{2,})\z/i, on: :save}
  validate :validate_domains

  before_save :emojify_default_fields, :guarantee_home_url_domain, :clean_domains!
  before_save :maybe_gravatar_for_avatar
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

  def maybe_gravatar_for_avatar
    return if avatar_image_path.present? || email.blank?

    # Ahh. This brings me back. Back to the days when
    # MD5 was the king of practical hashing hotness, and
    # geeks hadn't yet left it broken and bent to their evil bidding.
    email_hash = Digest::MD5.hexdigest(email.downcase.strip)
    # d=404 makes it return a 404 instead of giving us a default image
    gravatar_url = "https://www.gravatar.com/avatar/#{email_hash}.jpg?d=404"

    img_response = HTTParty.get(gravatar_url, follow_redirects: true, timeout: 10)
    if !img_response.success?
      if img_response.code == 404
        # set it to the missing avatar path so that
        # we don't try again and again every time the
        # profile is saved
        self.avatar_image_path = MISSING_AVATAR_PATH
      end
      return false
    end

    return unless img_response.success?

    url_sha = Digest::SHA2.hexdigest(gravatar_url)
    dir = archive_folder_path_for_doc(self)
    FileUtils.mkdir_p(dir)
    file_path = File.join(dir, "#{url_sha}.jpg")
    File.binwrite(file_path, img_response.body)
    self.avatar_image_path = "/" + file_path
  rescue => e
    Rails.logger.error "[Person] Failed to fetch Gravatar for #{email}: #{e.message}"
  end
end
