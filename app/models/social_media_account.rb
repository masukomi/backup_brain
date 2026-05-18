class SocialMediaAccount
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Pagination

  extend Search::ClassMethods
  include BackupBrain::ArchiveTools
  include Search::InstanceMethods

  VALID_TYPES = %w[personal professional unknown].freeze
  CONSOLIDATED_SERVICE_MAP = {
    "mastodon" => "mastodon", # https://joinmastodon.org/
    "pleroma" => "mastodon", # https://pleroma.social/
    "akkoma" => "mastodon", # https://akkoma.social/
    "gotosocial" => "gotosocial", # https://gotosocial.org/
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
    "bookwyrm" => "bookwyrm", # https://joinbookwyrm.com/
    "bski.app" => "bluesky",
    "twitter.com" => "fascist_transphobe",
    "x.com" => "fascist_transphobe",
    "threads.net" => "fascist_mysoginist"

  }.freeze
  SUPPORTED_SERVICES = CONSOLIDATED_SERVICE_MAP.select { |k, v|
    ["mastodon", "gotosocial", "misskey", "bookwyrm"].include?(v)
  }.keys.freeze

  field :service,           type: String
  field :profile_url,       type: String
  field :username,          type: String
  field :display_name,      type: String
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
      self.service = service.downcase
    elsif profile_url.present? # damn well better be
      self.service = SocialMediaAccount.query_service_type(profile_url)
    end
  end

  # NOTE: this is deriving the public URL of the user's
  # avatar on the service so that we can download it.
  def avatar_image_url
    return nil unless SocialMediaAccount.supported_service?(service)

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      extract_mastodon_avatar_image_url(remote_account_data)
    when "gotosocial"
      extract_gotosocial_avatar_image_url(remote_account_data)
    when "misskey"
      extract_misskey_avatar_image_url(remote_account_data)
    when "bookwyrm"
      extract_bookwyrm_avatar_image_url(remote_account_data)
    end
  end

  # NOTE: this is deriving the public URL of the header image on th
  # user's profile on the service so that we can download it.
  def header_image_url
    return nil unless SocialMediaAccount.supported_service?(service)

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      extract_mastodon_header_image_url(remote_account_data)
    when "gotosocial"
      extract_gotosocial_header_image_url(remote_account_data)
    when "misskey"
      extract_misskey_header_image_url(remote_account_data)
    when "bookwyrm"
      nil # BookWyrm profiles have no header/banner image
    end
  end

  def remote_description
    data = remote_account_data
    return nil unless data

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      extract_mastodon_user_description(data)
    when "gotosocial"
      extract_gotosocial_user_description(data)
    when "misskey"
      extract_misskey_user_description(data)
    when "bookwyrm"
      extract_bookwyrm_user_description(data)
    end
  end

  def remote_username
    data = remote_account_data
    return nil unless data

    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      extract_mastodon_full_username(data)
    when "gotosocial"
      extract_gotosocial_full_username(data)
    when "misskey"
      extract_misskey_full_username(data)
    when "bookwyrm"
      extract_bookwyrm_full_username(data)
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
      timeout: 30,
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
      timeout: 30,
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
    default_service_image_path(service, "avatar")
  end

  def default_header_image_path
    default_service_image_path(service, "header")
  end

  private

  def default_service_image_path(service, avatar_or_header)
    case CONSOLIDATED_SERVICE_MAP[service]
    when "mastodon"
      default_mastodon_image_path(avatar_or_header)
    when "gotosocial"
      default_gotosocial_image_path(avatar_or_header)
    when "misskey"
      default_misskey_image_path(avatar_or_header)
    when "bookwyrm"
      default_bookwyrm_image_path(avatar_or_header)
    end
  end

  # @param image_url [String|nil] hopefully fully qualified url to an image
  # @param filename [String] name you want to call the file without the extension
  #        ex. "header" or "avatar"
  # @param archive_folder_path [String] local archives path
  # @return nil or filename + extension
  def future_image_path_or_nil(image_url, file_name, archive_folder_path)
    return nil if image_url.blank?
    # NOTE: the URI.parse is needed because an url ending in
    # avatar.png?v=42 would return .png?v=42 as the extension
    # rescue nil because if they gave us something we can't parse as an url
    # there's no point in continuing
    ext = begin
      File.extname(URI.parse(image_url).path)
    rescue
      nil
    end
    return nil if ext.blank?
    File.join(archive_folder_path, "#{file_name}#{ext}")
  end

  def validated_image_url(image_url)
    return nil if image_url.blank?
    return nil if image_url == "missing.png" # mastodon's missing image image
    image_url
  end

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
    when "gotosocial"
      @remote_account_data ||= fetch_gotosocial_account_data
    when "misskey"
      @remote_account_data ||= fetch_misskey_account_data
    when "bookwyrm"
      @remote_account_data ||= fetch_bookwyrm_account_data
    else
      @remote_account_data = {}
    end
  end

  ######## MISSKEY METHODS
  def fetch_misskey_account_data
    uri = URI.parse(profile_url)
    base_url = "#{uri.scheme}://#{uri.host}"
    username = uri.path.split("/").last.delete_prefix("@")
    response = HTTParty.post(
      "#{base_url}/api/users/show",
      body: {username: username}.to_json,
      headers: {"Content-Type" => "application/json", "Accept" => "application/json"},
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return nil unless response.code == 200
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("SocialMediaAccount: failed to fetch Misskey account data for #{profile_url}: #{e.message}")
    nil
  end

  def default_misskey_image_path(avatar_or_header)
    misskey_key = (avatar_or_header == "avatar") ? "avatarUrl" : "bannerUrl"
    archive_folder_path = archive_folder_path_for_doc(self)
    future_image_path_or_nil(remote_account_data&.dig(misskey_key), avatar_or_header, archive_folder_path)
  end

  def extract_misskey_avatar_image_url(data)
    validated_image_url(data&.dig("avatarUrl"))
  end

  def extract_misskey_header_image_url(data)
    validated_image_url(data&.dig("bannerUrl"))
  end

  def extract_misskey_full_username(data)
    username = data&.dig("username")
    return nil if username.blank?
    host = data["host"]
    if host.blank?
      host = begin
        URI.parse(profile_url).host.downcase
      rescue
        nil
      end
    end
    return "@#{username}@#{host}" if host.present? && username.exclude?(host)
    "@#{username}"
  end

  def extract_misskey_user_description(data)
    note = data["description"].to_s.strip
    fields = (data["fields"] || []).map do |field|
      "**#{field["name"]}**: #{field["value"].to_s.strip}"
    end

    fields.reject!(&:empty?)
    if fields.present?
      (note + "\n\n-" + fields.join("  \n-"))
    else
      note
    end
  end

  ######## MASTODON METHODS
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

  def default_mastodon_image_path(avatar_or_header)
    archive_folder_path = archive_folder_path_for_doc(self)
    future_image_path_or_nil(remote_account_data&.dig(avatar_or_header), avatar_or_header, archive_folder_path)
  end

  def extract_mastodon_avatar_image_url(data)
    validated_image_url(remote_account_data&.dig("avatar"))
  end

  def extract_mastodon_header_image_url(data)
    validated_image_url(remote_account_data&.dig("header"))
  end

  def extract_mastodon_full_username(data)
    partial_username = data["acct"] # => mary
    return nil if partial_username.blank?
    host = begin
      URI.parse(profile_url).host.downcase
    rescue
      nil
    end
    return "@#{partial_username}@#{host}" if host.present? && partial_username.exclude?(host)
    "@#{partial_username}"
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

  def proxy_account_lookup_via_oauthed_mastodon(profile_url)
    mastodon_type = OauthSiteType.find_by(slug: "mastodon")
    # no point in continuing if we don't know about MastodonSiteTypes
    # That being said, this is in the seed data and should *never*
    # be nil
    return nil unless mastodon_type

    uri = URI.parse(profile_url)
    host = uri.host
    username = uri.path.split("/").last.delete_prefix("@")
    account = "#{username}@#{host}"

    # It's possible that one of the accounts you've authenticated with
    # isn't federated with the host of this profile url, so we'll
    # try multiple if present, and the 1st one doesn't work.
    sites = OauthSite.where(
      :oauth_site_type => mastodon_type,
      :base_url.nin => ["https://#{host}", "http://#{host}"]
    ).to_a

    return nil if sites.blank?

    # First pass: public lookup on each connected instance (no auth needed)
    sites.each do |site|
      data = lookup_via_oauthed_mastodon(site, account)
      return data if data.present?
    end

    # Second pass: authenticated resolve=true search to force federation
    sites.select { |s| s.access_token.present? }.each do |site|
      data = search_account_via_oauthed_mastodon(site, account)
      return data if data.present?
    end
  rescue => e
    Rails.logger.error("SocialMediaAccount: Mastodon proxy lookup failed for #{acct}: #{e.message}")
    nil
  end

  def lookup_account_via_oauthed_mastodon(oauth_site, account)
    response = HTTParty.get(
      "#{site.base_url}/api/v1/accounts/lookup",
      query: {acct: acct},
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return normalize_mastodon_to_activitypub(JSON.parse(response.body)) if response.code == 200
    nil
  end

  def search_account_via_oauthed_mastodon(oauth_site, account)
    response = HTTParty.get(
      "#{site.base_url}/api/v2/search",
      query: {q: "@#{acct}", resolve: "true", limit: 1, type: "accounts"},
      headers: {"Authorization" => "Bearer #{site.access_token}"},
      verify: false,
      timeout: 15,
      follow_redirects: true
    )
    return nil unless response.code == 200
    account_data = JSON.parse(response.body)["accounts"]&.first
    return normalize_mastodon_to_activitypub(account_data) if account_data
    nil
  end

  ######## GOTOSOCIAL METHODS
  # GoToSocial implements HTTP Signatures (sometimes called Linked Data
  # Signatures in the ActivityPub context, though that's a
  # slightly different spec). The specific RFC is RFC 9421 (HTTP
  # Message Signatures), though the fediverse largely
  # implemented an earlier draft spec before 9421 was finalized,
  # so you'll also see references to the older Cavage
  # draft (draft-cavage-http-signatures).
  #
  # Because of this, we can only get the info via an ActivityPub server
  # that can be reached by their host and implements HTTP Signatures.
  # For now, we're just supporting doing that via a Mastodon host that
  # you're authenticated with.

  def fetch_gotosocial_account_data
    # TODO: Add support for doing this via an OauthSite associated with an
    # OauthSiteType with the slug of `gotosocial`
    # only use proxy_account_lookup_via_oauthed_mastodon
    # if that fails.
    proxy_account_lookup_via_oauthed_mastodon(profile_url)
  end

  def normalize_mastodon_to_activitypub(data)
    avatar = data["avatar"]
    header = data["header"]
    {
      "preferredUsername" => data["acct"]&.split("@")&.first,
      "icon" => avatar.present? ? {"url" => avatar} : nil,
      "image" => header.present? ? {"url" => header} : nil,
      "summary" => data["note"],
      "attachment" => (data["fields"] || []).map { |f|
        {"type" => "PropertyValue", "name" => f["name"], "value" => f["value"]}
      }
    }
  end

  def default_gotosocial_image_path(avatar_or_header)
    archive_folder_path = archive_folder_path_for_doc(self)
    image_url = if avatar_or_header == "avatar"
      remote_account_data&.dig("icon", "url")
    else
      remote_account_data&.dig("image", "url")
    end
    future_image_path_or_nil(image_url, avatar_or_header, archive_folder_path)
  end

  def extract_gotosocial_avatar_image_url(data)
    validated_image_url(data&.dig("icon", "url"))
  end

  def extract_gotosocial_header_image_url(data)
    validated_image_url(data&.dig("image", "url"))
  end

  def extract_gotosocial_full_username(data)
    username = data&.dig("preferredUsername")
    return nil if username.blank?
    host = begin
      URI.parse(profile_url).host.downcase
    rescue
      nil
    end
    host.present? ? "@#{username}@#{host}" : "@#{username}"
  end

  def extract_gotosocial_user_description(data)
    note = ReverseMarkdown.convert(data["summary"].to_s).strip
    fields = Array(data["attachment"])
      .select { |a| a["type"] == "PropertyValue" }
      .map { |a| "**#{a["name"]}**: #{ReverseMarkdown.convert(a["value"].to_s).strip}" }
      .reject(&:empty?)
    fields.present? ? (note + "\n\n-" + fields.join("  \n-")) : note
  end

  ######## BOOKWYRM METHODS
  def fetch_bookwyrm_account_data
    response = HTTParty.get(
      profile_url,
      headers: {"Accept" => "application/activity+json"},
      verify: false,
      timeout: 10,
      follow_redirects: true
    )
    return nil unless response.code == 200
    JSON.parse(response.body)
  rescue => e
    Rails.logger.error("SocialMediaAccount: failed to fetch BookWyrm account data for #{profile_url}: #{e.message}")
    nil
  end

  def default_bookwyrm_image_path(avatar_or_header)
    return nil unless avatar_or_header == "avatar"
    archive_folder_path = archive_folder_path_for_doc(self)
    future_image_path_or_nil(remote_account_data&.dig("icon", "url"), "avatar", archive_folder_path)
  end

  def extract_bookwyrm_avatar_image_url(data)
    validated_image_url(data&.dig("icon", "url"))
  end

  def extract_bookwyrm_header_image_url(_data)
    nil
  end

  def extract_bookwyrm_full_username(data)
    username = data&.dig("preferredUsername")
    return nil if username.blank?
    host = begin
      URI.parse(profile_url).host.downcase
    rescue
      nil
    end
    host.present? ? "@#{username}@#{host}" : "@#{username}"
  end

  def extract_bookwyrm_user_description(data)
    ReverseMarkdown.convert(data["summary"].to_s).strip
  end
end
