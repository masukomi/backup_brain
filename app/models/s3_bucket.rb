class S3Bucket
  include Mongoid::Document
  include Mongoid::Timestamps

  # your name for this bucket
  field :nickname,                type: String

  # indicates if the system should use this bucket or not.
  field :enabled,                 type: Boolean, default: false

  # indicates if the system should treat this bucket as the primary
  # (the one downloads and presigned urls come from). Only one bucket
  # is primary at a time; the first bucket to be enabled becomes it.
  field :primary,                 type: Boolean, default: false

  # Endpoint URL of your S3 compatible service
  # The base URL of the S3 API, e.g. https://s3.us-west-004.backblazeb2.com,
  # https://<account_id>.r2.cloudflarestorage.com or http://localhost:9000 for MinIO.
  # Leave blank to use AWS S3 (the region setting is used instead).
  field :endpoint,                type: String

  # Region of your S3 bucket
  # AWS region name such as us-east-1. Many S3 compatible services accept
  # any value here (Cloudflare R2 uses "auto"). Defaults to us-east-1
  field :region,                  type: String, default: "us-east-1"

  # Name of the PRIVATE bucket archived assets are stored in",
  # The bucket must NOT allow public reads. BackupBrain generates
  # presigned URLs for every download, so a public bucket would defeat
  # the access restriction.
  field :name,                    type: String

  # Access key ID (token id) issued by your S3 compatible service
  # The identifier half of the credentials your service issued for BackupBrain.
  # Backblaze calls this the keyID, Cloudflare R2 the Access Key ID
  # MinIO the Access Key. Grant it read, write and list access to the bucket above.
  field :access_key_id,           type: String

  # Secret access key (token secret) issued by your S3 compatible service
  # The secret half of the credentials. Backblaze calls this the applicationKey
  # Cloudflare R2 and MinIO the Secret Access Key. Keep it private.
  field :secret_access_key,       type: String

  # Optional folder (key prefix) inside the bucket
  # Lets several apps share one bucket. For example backup_brain stores
  # objects as backup_brain/bookmarks/<id>/<file>. Leave blank to store them
  # at the root of the bucket. Don't change this after uploading.
  field :key_prefix,              type: String, default: ""

  # Seconds a presigned download URL stays valid
  # When a browser asks BackupBrain for an archived asset that lives
  # in S3, BackupBrain redirects it to a presigned URL that expires after
  # this many seconds. One hour (3600) is plenty for a page load; S3 caps
  # presigned URLs at 7 days (604800).
  field :presigned_url_expiry,    type: Integer, default: 3600

  # Most S3 compatible services (MinIO, Garage, Backblaze, R2)
  # want path-style addressing. Set to false for virtual-host
  # style (https://bucket.endpoint/key), which AWS S3 prefers.
  field :path_style_urls,         type: Boolean, default: true

  MAX_PRESIGNED_URL_EXPIRY = 604_800 # 7 days, the S3 cap

  # endpoint and key_prefix are legitimately blank (AWS / bucket root).
  validates :nickname,
    :region,
    :name,
    :access_key_id,
    :secret_access_key,
    presence: true
  validates :nickname, uniqueness: true
  # presence: true rejects false, so booleans get an inclusion check instead
  validates :enabled, :primary, :path_style_urls, inclusion: {in: [true, false]}
  validates :presigned_url_expiry,
    numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_PRESIGNED_URL_EXPIRY}
  validate :enabled_primaries_only

  before_validation :strippers
  before_validation :become_primary_if_alone
  after_destroy :reload_storage
  after_save :demote_other_primaries
  after_save :reload_storage

  # CLASS METHODS ------------------------
  class << self
    # @return [Boolean] true when there is at least 1 S3Bucket configured and enabled
    def any_enabled?
      enabled_buckets.exists?
    end

    # @return [S3Bucket, NilClass] the bucket that should be used as the primary or nil
    def primary_bucket
      where(primary: true).first
    end

    # @return [Mongoid::Criteria<S3Bucket>]
    def enabled_buckets
      where(enabled: true)
    end
  end

  # INSTANCE METHODS ------------------------

  # A disabled bucket can't be the primary: reads would go nowhere.
  def enabled_primaries_only
    if primary && !enabled
      errors.add(:primary, I18n.t("s3_buckets.errors.enabled_primaries_only"))
    end
  end

  # strip leading and trailing spaces from all String fields before validating
  def strippers
    self.class.fields.each_value do |f|
      next unless f.options[:type] == String
      value = send(f.name)
      send(:"#{f.name}=", value.strip) if value.is_a?(String)
    end
  end

  private

  # The first enabled bucket is the primary by default.
  def become_primary_if_alone
    return unless enabled && !primary
    self.primary = true unless other_primaries.any?
  end

  # Only one bucket is primary at a time.
  def demote_other_primaries
    return unless primary
    # update_all on purpose: demoting mustn't trigger the demoted buckets'
    # own callbacks (which would reload storage and re-check primaries).
    other_primaries.update_all(primary: false) # rubocop:disable Rails/SkipsModelValidations
  end

  # @return [Mongoid::Criteria<S3Bucket>] every other bucket marked primary
  def other_primaries
    self.class.where(:primary => true, :_id.ne => _id)
  end

  # Make sure S3Storage works with the current buckets and credentials.
  def reload_storage
    BackupBrain::S3Storage.reload!
  end
end
