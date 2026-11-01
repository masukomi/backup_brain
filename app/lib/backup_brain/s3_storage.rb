require "aws-sdk-s3"
require "rack/mime"

module BackupBrain
  # Optional remote storage of archived assets on any S3-compatible service
  # (AWS S3, Cloudflare R2, Backblaze B2, MinIO, Garage, …).
  #
  # Connection details live in S3Bucket documents. Every *enabled* bucket
  # receives a copy of each uploaded file and loses its copy on delete.
  # Reads (exists?, download, presigned urls) go to the *primary* bucket
  # unless another bucket is passed explicitly.
  #
  # Object keys mirror the on-disk layout under archives/:
  #   archives/bookmarks/<id>/<sha256>.mp3  →  <prefix>bookmarks/<id>/<sha256>.mp3
  # where <prefix> is the bucket's own key_prefix, so the same file can sit
  # at different keys in different buckets.
  #
  # Buckets are expected to be private. Nothing is ever served straight from
  # a bucket; BackupBrain hands out short-lived presigned URLs instead, so an
  # asset can only be fetched when the request started here.
  #
  # Three URL / path flavours show up around this class:
  # - local path:  "archives/bookmarks/<id>/<file>" (relative to Rails.root)
  # - web path:    "/archives/bookmarks/<id>/<file>" (what ArchivesController serves)
  # - s3 url:      "s3://<bucket>/<key>" (stored in MediaObject#url once migrated)
  class S3Storage
    SCHEME = "s3://".freeze

    class << self
      def instance
        @instance ||= new
      end

      # Drops the memoized instance (and its clients). S3Bucket calls this
      # after every save / destroy so configuration changes take effect
      # without a restart.
      def reload!
        @instance = nil
      end

      # @return [Boolean] true when at least one S3Bucket is enabled
      def enabled?
        S3Bucket.any_enabled?
      end

      def s3_url?(url)
        url.to_s.start_with?(SCHEME)
      end
    end

    # INSTANCE METHODS -----------

    # @return [S3Bucket, nil] the bucket reads default to
    attr_reader :bucket

    def initialize
      @bucket = S3Bucket.primary_bucket
      @clients = {}
    end

    # The bucket's key prefix normalised to "" or "something/".
    #
    # @param s3_bucket [S3Bucket]
    # @return [String]
    def key_prefix(s3_bucket = @bucket)
      prefix = s3_bucket.key_prefix.to_s.strip.delete_prefix("/")
      return "" if prefix.empty?
      prefix.end_with?("/") ? prefix : "#{prefix}/"
    end

    # One memoized client per bucket configuration.
    #
    # @param s3_bucket [S3Bucket]
    # @return [Aws::S3::Client]
    def client(s3_bucket = @bucket)
      config = client_config(s3_bucket)
      @clients[config] ||= Aws::S3::Client.new(**config)
    end

    # --- key / path / url conversions ---------------------------------------

    # "archives/bookmarks/<id>/f.mp3" (or absolute under Rails.root) → key
    def key_for_local_path(local_path, s3_bucket = @bucket)
      relative = local_path.to_s.delete_prefix(Rails.root.to_s).delete_prefix("/")
      relative = relative.delete_prefix("#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/")
      "#{key_prefix(s3_bucket)}#{relative}"
    end

    # "/archives/bookmarks/<id>/f.mp3" → key
    def key_for_web_path(web_path, s3_bucket = @bucket)
      key_for_local_path(web_path.to_s.delete_prefix("/"), s3_bucket)
    end

    # "s3://bucket_name/key" → key
    #
    # Without an explicit bucket the url may name any known S3Bucket (an s3
    # url recorded while another bucket was primary still resolves). With
    # one, the url must name that bucket.
    #
    # @return [String, nil] nil when the url isn't ours
    def key_for_s3_url(url, s3_bucket = nil)
      return nil unless self.class.s3_url?(url)
      url_bucket, key = url.to_s.delete_prefix(SCHEME).split("/", 2)
      return nil if key.blank?
      s3_bucket ||= bucket_named(url_bucket)
      return nil if s3_bucket.nil? || url_bucket != s3_bucket.name
      key
    end

    # Accepts a web path, local path or s3 url.
    def key_for(url_or_path, s3_bucket = @bucket)
      return key_for_s3_url(url_or_path, s3_bucket) if self.class.s3_url?(url_or_path)
      return key_for_web_path(url_or_path, s3_bucket) if url_or_path.to_s.start_with?("/")
      key_for_local_path(url_or_path, s3_bucket)
    end

    # The S3Bucket an s3 url points at.
    #
    # @return [S3Bucket, nil]
    def bucket_for_s3_url(url)
      return nil unless self.class.s3_url?(url)
      bucket_named(url.to_s.delete_prefix(SCHEME).split("/", 2).first)
    end

    # Like remote_storage_has? but for a path without an extension:
    # returns the web path of the first object whose key starts with it.
    #
    # @return [String, nil]
    def web_path_for_path_prefix(local_path_prefix, s3_bucket = @bucket)
      key = first_key_with_prefix(
        key_for_local_path(local_path_prefix, s3_bucket),
        s3_bucket
      )
      key ? web_path_for_key(key, s3_bucket) : nil
    end

    # key → "/archives/bookmarks/<id>/f.mp3" (the bucket's prefix is stripped)
    def web_path_for_key(key, s3_bucket = @bucket)
      "/#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/#{key.to_s.delete_prefix(key_prefix(s3_bucket))}"
    end

    # "s3://bucket_name/key" → "/archives/bookmarks/<id>/f.mp3"
    #
    # @return [String, nil] nil when the url names a bucket we don't know
    def web_path_for_s3_url(url)
      s3_bucket = bucket_for_s3_url(url)
      key = key_for_s3_url(url, s3_bucket)
      key ? web_path_for_key(key, s3_bucket) : nil
    end

    def s3_url_for_key(key, s3_bucket = @bucket)
      "#{SCHEME}#{s3_bucket.name}/#{key}"
    end

    def s3_url_for_web_path(web_path, s3_bucket = @bucket)
      s3_url_for_key(key_for_web_path(web_path, s3_bucket), s3_bucket)
    end

    # --- remote operations --------------------------------------------------

    # Uploads a copy of a local file to every enabled bucket, at each
    # bucket's own key for that path.
    #
    # @param local_file_path [String] e.g. "archives/bookmarks/<id>/<sha>.mp3"
    # @return [Boolean] true
    def upload_local_file(local_file_path, content_type: nil)
      S3Bucket.enabled_buckets.each do |s3_bucket|
        key = key_for_local_path(local_file_path, s3_bucket)
        upload(local_file_path, key, s3_bucket, content_type: content_type)
      end
      true
    end

    # Uploads a local file to one bucket, unless the key is already there.
    # Content-Type is derived from the extension so browsers render images /
    # play audio from the presigned URL.
    #
    # @return [Boolean] true
    def upload(local_path, key, s3_bucket = @bucket, content_type: nil)
      return true if exists?(key, s3_bucket)
      content_type ||= Rack::Mime.mime_type(File.extname(local_path), "application/octet-stream")
      File.open(local_path, "rb") do |io|
        client(s3_bucket).put_object(bucket: s3_bucket.name, key: key, body: io, content_type: content_type)
      end
      true
    end

    # @return [Aws::S3::Types::HeadObjectOutput, nil]
    def head(key, s3_bucket = @bucket)
      client(s3_bucket).head_object(bucket: s3_bucket.name, key: key)
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end

    # @return [Boolean] true when the key exists in the given bucket
    #   (the primary by default)
    def exists?(key, s3_bucket = @bucket)
      return false unless s3_bucket
      !head(key, s3_bucket).nil?
    end

    # First key under +prefix+, or nil. Used when the extension of an archived
    # asset isn't known up front (see Archiver#download_asset).
    def first_key_with_prefix(prefix, s3_bucket = @bucket)
      client(s3_bucket).list_objects_v2(
        bucket: s3_bucket.name,
        prefix: prefix,
        max_keys: 1
      ).contents.first&.key
    end

    def download(key, to_path, s3_bucket = @bucket)
      FileUtils.mkdir_p(File.dirname(to_path))
      client(s3_bucket).get_object(bucket: s3_bucket.name, key: key, response_target: to_path)
      to_path
    end

    # Deletes the object behind a web path, local path or s3 url from every
    # enabled bucket. An s3 url is first mapped back to its web path, so the
    # copies in the other buckets (which have their own keys) go too.
    #
    # @return [Boolean] true
    def delete_url(url)
      path = self.class.s3_url?(url) ? web_path_for_s3_url(url) : url
      return true if path.blank?
      S3Bucket.enabled_buckets.each do |s3_bucket|
        key = key_for(path, s3_bucket)
        next if key.blank?
        client(s3_bucket).delete_object(bucket: s3_bucket.name, key: key)
      end
      true
    end

    # Deletes every object under a local "folder" from every enabled bucket.
    # +local_folder+ must end with "/" so a bookmark id can't match a sibling
    # that merely starts the same way.
    #
    # @param local_folder [String] e.g. "archives/bookmarks/<id>/"
    # @return [Integer] number of objects deleted. With several enabled
    #   buckets every copy counts, so this is a multiple of the number of
    #   files.
    def delete_prefix(local_folder)
      raise ArgumentError, "prefix must end with /" unless local_folder.to_s.end_with?("/")
      deleted = 0
      S3Bucket.enabled_buckets.each do |s3_bucket|
        deleted += delete_prefix_in_bucket(key_for_local_path(local_folder, s3_bucket), s3_bucket)
      end
      deleted
    end

    def presigned_url(key, s3_bucket = @bucket, expires_in: nil)
      Aws::S3::Presigner.new(client: client(s3_bucket))
        .presigned_url(
          :get_object,
          bucket: s3_bucket.name,
          key: key,
          expires_in: expires_in || s3_bucket.presigned_url_expiry
        )
    end

    private

    # @return [S3Bucket, nil]
    def bucket_named(name)
      return nil if name.blank?
      return @bucket if @bucket&.name == name
      S3Bucket.where(name: name).first
    end

    # @return [Integer] number of objects deleted
    def delete_prefix_in_bucket(prefix, s3_bucket)
      deleted = 0
      continuation_token = nil
      current_client = client(s3_bucket)
      loop do
        page = current_client.list_objects_v2(
          bucket: s3_bucket.name,
          prefix: prefix,
          continuation_token: continuation_token
        )
        keys = page.contents.map { |object| {key: object.key} }
        unless keys.empty?
          current_client.delete_objects(
            bucket: s3_bucket.name,
            delete: {objects: keys, quiet: true}
          )
          deleted += keys.size
        end
        break unless page.is_truncated
        continuation_token = page.next_continuation_token
      end
      deleted
    end

    def client_config(s3_bucket)
      # note: endpoint is blank for AWS
      endpoint = s3_bucket.endpoint.to_s
      config = {
        region: s3_bucket.region,
        access_key_id: s3_bucket.access_key_id,
        secret_access_key: s3_bucket.secret_access_key,
        force_path_style: s3_bucket.path_style_urls != false
      }
      config[:endpoint] = endpoint if endpoint.present?
      config
    end
  end
end
