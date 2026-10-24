require "aws-sdk-s3"
require "rack/mime"

module BackupBrain
  # Optional remote storage of archived assets on any S3-compatible service
  # (AWS S3, Cloudflare R2, Backblaze B2, MinIO, Garage, …).
  #
  # Object keys mirror the on-disk layout under archives/:
  #   archives/bookmarks/<id>/<sha256>.mp3  →  <prefix>bookmarks/<id>/<sha256>.mp3
  #
  # The bucket is expected to be private. Nothing is ever served straight from
  # the bucket; BackupBrain hands out short-lived presigned URLs instead, so an
  # asset can only be fetched when the request started here.
  #
  # Three URL / path flavours show up around this class:
  # - local path:  "archives/bookmarks/<id>/<file>" (relative to Rails.root)
  # - web path:    "/archives/bookmarks/<id>/<file>" (what ArchivesController serves)
  # - s3 url:      "s3://<bucket>/<key>" (stored in MediaObject#url once migrated)
  class S3Storage
    SCHEME = "s3://".freeze
    SETTING_KEYS = %w[
      enable_s3_storage s3_endpoint s3_region s3_bucket s3_access_key_id
      s3_secret_access_key s3_key_prefix s3_force_path_style s3_presigned_url_expiry
    ].freeze
    DEFAULT_EXPIRY = 3600

    def self.instance
      @instance ||= new
    end

    def self.reload!
      @instance = nil
    end

    # @return [Boolean] true when the feature flag is on AND the connection
    #   details are present.
    def self.enabled?
      setting("enable_s3_storage") == true && configured?
    end

    # @return [Boolean] true when bucket + credentials are filled in.
    def self.configured?
      %w[s3_bucket s3_access_key_id s3_secret_access_key].all? { |k| setting(k).to_s.strip.present? }
    end

    def self.s3_url?(url)
      url.to_s.start_with?(SCHEME)
    end

    def self.setting(key)
      Setting.get_value_of_key(key, safe: true)
    end

    def bucket
      self.class.setting("s3_bucket").to_s.strip
    end

    def key_prefix
      prefix = self.class.setting("s3_key_prefix").to_s.strip.delete_prefix("/")
      return "" if prefix.empty?
      prefix.end_with?("/") ? prefix : "#{prefix}/"
    end

    def expiry
      value = self.class.setting("s3_presigned_url_expiry")
      (value.is_a?(Integer) && value.positive?) ? value : DEFAULT_EXPIRY
    end

    # Memoized per configuration, so changing a setting takes effect
    # without a restart.
    def client
      config = client_config
      if @client.nil? || @client_config != config
        @client_config = config
        @client = Aws::S3::Client.new(**config)
      end
      @client
    end

    # --- key / path / url conversions ---------------------------------------

    # "archives/bookmarks/<id>/f.mp3" (or absolute under Rails.root) → key
    def key_for_local_path(local_path)
      relative = local_path.to_s.delete_prefix(Rails.root.to_s).delete_prefix("/")
      relative = relative.delete_prefix("#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/")
      "#{key_prefix}#{relative}"
    end

    # "/archives/bookmarks/<id>/f.mp3" → key
    def key_for_web_path(web_path)
      key_for_local_path(web_path.to_s.delete_prefix("/"))
    end

    # "s3://bucket/key" → key (nil when the url isn't ours)
    def key_for_s3_url(url)
      return nil unless self.class.s3_url?(url)
      rest = url.to_s.delete_prefix(SCHEME)
      url_bucket, key = rest.split("/", 2)
      return nil if url_bucket != bucket || key.blank?
      key
    end

    # Accepts a web path, local path or s3 url.
    def key_for(url_or_path)
      return key_for_s3_url(url_or_path) if self.class.s3_url?(url_or_path)
      return key_for_web_path(url_or_path) if url_or_path.to_s.start_with?("/")
      key_for_local_path(url_or_path)
    end

    def web_path_for_key(key)
      "/#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/#{key.to_s.delete_prefix(key_prefix)}"
    end

    def web_path_for_s3_url(url)
      key = key_for_s3_url(url)
      key ? web_path_for_key(key) : nil
    end

    def s3_url_for_key(key)
      "#{SCHEME}#{bucket}/#{key}"
    end

    def s3_url_for_web_path(web_path)
      s3_url_for_key(key_for_web_path(web_path))
    end

    # --- remote operations --------------------------------------------------

    # Uploads a local file. Content-Type is derived from the extension so
    # browsers render images / play audio from the presigned URL.
    def upload(local_path, key, content_type: nil)
      content_type ||= Rack::Mime.mime_type(File.extname(local_path), "application/octet-stream")
      File.open(local_path, "rb") do |io|
        client.put_object(bucket: bucket, key: key, body: io, content_type: content_type)
      end
      true
    end

    # @return [Aws::S3::Types::HeadObjectOutput, nil]
    def head(key)
      client.head_object(bucket: bucket, key: key)
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end

    def exists?(key)
      !head(key).nil?
    end

    # First key under +prefix+, or nil. Used when the extension of an archived
    # asset isn't known up front (see Archiver#download_asset).
    def first_key_with_prefix(prefix)
      client.list_objects_v2(bucket: bucket, prefix: prefix, max_keys: 1).contents.first&.key
    end

    def download(key, to_path)
      FileUtils.mkdir_p(File.dirname(to_path))
      client.get_object(bucket: bucket, key: key, response_target: to_path)
      to_path
    end

    def delete(key)
      client.delete_object(bucket: bucket, key: key)
      true
    end

    # Deletes every object under a "folder". +prefix+ must end with "/" so a
    # bookmark id can't match a sibling that merely starts the same way.
    #
    # @return [Integer] number of objects deleted
    def delete_prefix(prefix)
      raise ArgumentError, "prefix must end with /" unless prefix.to_s.end_with?("/")
      deleted = 0
      continuation_token = nil
      loop do
        page = client.list_objects_v2(bucket: bucket, prefix: prefix, continuation_token: continuation_token)
        keys = page.contents.map { |object| {key: object.key} }
        unless keys.empty?
          client.delete_objects(bucket: bucket, delete: {objects: keys, quiet: true})
          deleted += keys.size
        end
        break unless page.is_truncated
        continuation_token = page.next_continuation_token
      end
      deleted
    end

    def presigned_url(key, expires_in: expiry)
      Aws::S3::Presigner.new(client: client)
        .presigned_url(:get_object, bucket: bucket, key: key, expires_in: expires_in)
    end

    # Presigned URL for a web path, local path or s3 url.
    def presigned_url_for(url_or_path, expires_in: expiry)
      presigned_url(key_for(url_or_path), expires_in: expires_in)
    end

    private

    def client_config
      endpoint = self.class.setting("s3_endpoint").to_s.strip
      region = self.class.setting("s3_region").to_s.strip
      config = {
        region: region.presence || "us-east-1",
        access_key_id: self.class.setting("s3_access_key_id").to_s.strip,
        secret_access_key: self.class.setting("s3_secret_access_key").to_s.strip,
        force_path_style: self.class.setting("s3_force_path_style") != false
      }
      config[:endpoint] = endpoint if endpoint.present?
      config
    end
  end
end
