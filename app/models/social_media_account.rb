class SocialMediaAccount
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  extend BackupBrain::ArchiveTools
  include Search::InstanceMethods

  VALID_TYPES = %w[personal professional unknown].freeze
  CONSOLIDATED_SERVICE_MAP = {
    "mastodon" => "mastodon", # https://joinmastodon.org/
    "pleroma" => "mastodon", # https://pleroma.social/
    "akkoma" => "mastodon", # https://akkoma.social/
    "gotosocial" => "mastodon", # https://gotosocial.org/
    "hometown" => "mastodon", # https://github.com/hometown-fork/hometown
    "snac" => "mastodon", # https://codeberg.org/grunfink/snac2/
    "takahe" => "mastodon", # https://jointakahe.org/
    # should work for this, but won't work for bookmark importing
    # --
    # "glitch-soc" => "mastodon", # https://glitch-soc.github.io/docs/
    # glitch-soc reports itself as "mastodon"
    # --
    # "rebased" => "mastodon"
    # rebased reports itself as "pleroma"
    "misskey" => "misskey", # https://misskey-hub.net/
    "calckey" => "misskey", # A.K.A. Firefish (discontinued)
    "firefish" => "misskey",
    "iceshrimp" => "misskey",
    "sharkey" => "misskey",
    "foundkey" => "misskey",
    "cherrypick" => "misskey",
    "bski.app" => "bluesky",
    "twitter.com" => "fascist_transphobe",
    "x.com" => "fascist_transphobe",
    "threads.net" => "fascist_mysoginist"

  }.freeze
  SUPPORTED_SERVICES = CONSOLIDATED_SERVICE_MAP.select { |k, v| v == "mastodon" }.keys.freeze

  field :service,           type: String
  field :profile_url,       type: String
  field :username,          type: String
  field :avatar_image_path, type: String # path to avatar image
  # typically /archives/social_media_accounts/<id>/avatar.<extension>
  field :header_image_path, type: String # path to header image
  # typically /archives/social_media_accounts/<id>/header.<extension>
  field :description,       type: String
  field :type,              type: String
  field :preferred,         type: Boolean, default: false

  belongs_to :person, optional: true

  has_and_belongs_to_many :bookmarks
  # a direct association to a bookmark indicates that this
  # social media account is responsible for posting
  # the thing we bookmarked.
  # It is not uncommon for this to be blank.

  validates :profile_url, presence: true
  validates :type, inclusion: {in: VALID_TYPES}

  # TODO: before we save a new SocialMediaAccount
  # the controller should verify that the service returned by
  # query_service_type(profile_url) matches service
  # the user specified, OR use the output to
  # choose / set service
  before_save :standardize_service
  after_create :schedule_archive_job, if: -> { SocialMediaAccount.supported_service?(service) && !@skip_auto_archive_job }
  after_save :demote_sibling_accounts, if: -> { preferred? && preferred_previously_changed? }

  def standardize_service
    if service.present?
      service&.downcase # shouldn't be needed unless we make this user editable
    elsif profile_url.present? # damn well better be
      SocialMediaAccount.query_service_type(profile_url)
    end
  end

  # NOTE: this is deriving the public URL of the user's
  # avatar on the service so that we can download it.
  def avatar_image_url
    return nil unless SocialMediaAccount.supported_service?(service)

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      remote_account_data&.dig("avatar")
    end
  end

  # NOTE: this is deriving the public URL of the header image on th
  # user's profile on the service so that we can download it.
  def header_image_url
    return nil unless SocialMediaAccount.supported_service?(service)

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      remote_account_data&.dig("header")
    end
  end

  def remote_description
    data = remote_account_data
    return nil unless data

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      extract_mastodon_user_description(data)
    end
  end

  def extract_mastodon_user_description(data)
    note = ReverseMarkdown.convert(data["note"].to_s).strip
    fields = (data["fields"] || []).map do |field|
      "**#{field["name"]}**: #{ReverseMarkdown.convert(field["value"].to_s).strip}"
    end

    fields.reject!(&:empty?)
    if fields.present?
      (note + "\n\n-" + fields.join("  \n-"))
    else
      note
    end
  end

  def has_supported_service?
    # it's not so much if we support that particular "service"
    # as if we support the API underlying it or not.
    SocialMediaAccount.supported_service?(CONSOLIDATED_SERVICE_MAP[service])
  end

  def self.supported_service?(service)
    SUPPORTED_SERVICES.include?(service)
  end

  # Known Fediverse software.name values returned by NodeInfo:
  # Mastodon-compatible (support Mastodon API):
  #   mastodon, pleroma, akkoma, gotosocial
  # Misskey-family (use Misskey API):
  #   misskey, calckey, firefish, iceshrimp, sharkey, foundkey, cherrypick
  # Other ActivityPub:
  #   pixelfed, peertube, funkwhale, bookwyrm, writefreely, plume,
  #   friendica, hubzilla, streams, lemmy, kbin, mbin, honk, snac
  # Note: diaspora* uses its own protocol and may not expose NodeInfo
  #
  # NOTE: twitter.com, x.com, threads.net, bsky.app are all known domains
  # we can test instead of using .well-known/nodeinfo
  # BUT I think twitter killed their API and I'm not going to write one
  # for the others so I'm not sure it matters.
  def self.query_service_type(profile_url)
    uri = URI.parse(profile_url)

    base_url = "#{uri.scheme}://#{uri.host}"

    response = HTTParty.get(
      "#{base_url}/.well-known/nodeinfo",
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return nil unless response.code == 200
    nodeinfo_index = JSON.parse(response.body)

    # Prefer the highest schema version available
    link = nodeinfo_index["links"]
      &.select { |l| l["rel"].to_s.include?("nodeinfo.diaspora.software") }
      &.max_by { |l| l["rel"].to_s }
    return nil if link&.dig("href").blank?

    info_response = HTTParty.get(
      link["href"],
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return nil unless info_response.code == 200
    JSON.parse(info_response.body).dig("software", "name")&.downcase&.strip
  rescue => e
    Rails.logger.error("SocialMediaAccount: NodeInfo lookup failed for #{profile_url}: #{e.message}")
    nil
  end

  # @return [String] the name of the service who's API their share
  #                  or itself if it doesn't replicate another service's API
  def self.service_to_api_type(service)
    CONSOLIDATED_SERVICE_MAP.fetch(name, name) # return what it maps to or itself.
    # thus "gotosocial" becomes "mastodon" and "pixelfed" stays "pixelfed"
  end

  # URI.parse(...).path strips query strings before File.extname runs, so URLs
  # like https://cdn.example.com/avatar.jpg?v=123 will correctly yield .jpg. If
  # remote_account_data is nil or the URL has no extension, ext will be "" and
  # the path falls back to extensionless — which is fine since download_asset
  # will still detect it post-download.

  def default_avatar_image_path
    archive_folder_path = archive_folder_path_for(self)
    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      ext = File.extname(URI.parse(remote_account_data&.dig("avatar").to_s).path)
      return File.join(archive_folder_path, "avatar#{ext}")
    end
    nil
  end

  def default_header_image_path
    archive_folder_path = archive_folder_path_for(self)
    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      ext = File.extname(URI.parse(remote_account_data&.dig("header").to_s).path)
      return File.join(archive_folder_path, "header#{ext}")
    end
    nil
  end

  private

  # rubocop:disable Rails/SkipsModelValidations
  # No need to validate since they're already saved
  # and we're just toggling a boolean field that
  # is always valid in either state
  def demote_sibling_accounts
    return unless person
    # Aww We're sorry. They still love you. Probably…
    person.social_media_accounts
      .where(:id.ne => _id, :preferred => true)
      .update_all(preferred: false)
  end
  # rubocop:enable Rails/SkipsModelValidations

  def suppress_auto_archive_job!
    @skip_auto_archive_job = true
  end

  def schedule_archive_job
    ArchiveSocialMediaAccountJob.perform_later(social_media_account_id: _id.to_s)
  end

  def remote_account_data
    return @remote_account_data unless @remote_account_data.nil?

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      @remote_account_data ||= fetch_mastodon_account_data
    else
      @remote_account_data = {}
    end
  end

  def fetch_mastodon_account_data
    uri = URI.parse(profile_url)
    base_url = "#{uri.scheme}://#{uri.host}"
    username = uri.path.split("/").last.delete_prefix("@")
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/lookup",
      query: {acct: username},
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return nil unless response.code == 200
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("SocialMediaAccount: failed to fetch Mastodon account data for #{profile_url}: #{e.message}")
    nil
  end
end
