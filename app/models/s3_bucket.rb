class S3Bucket
  include Mongoid::Document
  include Mongoid::Timestamps


  # your name for this bucket
  field :nickname,                type: String

  # indicates if the system should use this bucket or not.
  field :enabled,                 type: Boolean, default: false

  # indicates if the system should treat this bucket as the primary
  field :primary,                 type: Boolean, default: true
  
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
  field :key_prefix,              type: String

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

  validates :nickname,
            :enabled,
            :primary,
            # I'd like to validate endpoint
            # I think it needs to be blank for AWS
            # :endpoint,
            :region,
            :name,
            :access_key_id,
            :secret_access_key,
            :key_prefix,
            :presigned_url_expiry,
            :path_style_urls,
            presence: true
  
  validate :enabled_primaries_only
  before_save :strippers
  after_save :im_the_primary
  
  # CLASS METHODS ------------------------
  class << self
    # @return [Boolean] true when there is at least 1 S3Bucket configured and enabled
    def any_enabled?
      S3Bucket.where(enabled: true).count > 0
    end

    # @return [S3Bucket, NilClass] the bucket that should be used as the primary or nil
    def primary_bucket
      S3Bucket.where(primary: true).first
    end

    def enabled_buckets
      S3Bucket.where(enabled: true)
    end
 end

  # INSTANCE METHODS ------------------------
  def enabled_primaries_only
    if primary && ! enabled
      errors.add(:primary, I18n.t('s3_buckets.errors.only_enabled_primaries'))
    end
  end

  def im_the_primary
    if primary
      #TODO update all S3Bucket objects except this one & set primary to false
      # make sure S3Storage is working with the correct primary
      S3Storage.reload!
    end
  end

  # strip leading and trailing spaces from all String fields before saving
  def strippers
    field_names = S3Bucket.fields.select{|k, f| f.options[:type] == String }.keys
    field_names.each do | fn |
      self.send("#{fn}=".to_sym, self.send("#{fn}")&.strip)
    end
  end
end
