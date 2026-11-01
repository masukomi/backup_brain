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

    class << self
      def instance
        @instance ||= new
      end

      def reload!
        @instance = nil
      end

      # @return [Boolean] true when the feature flag is on AND the connection
      #   details are present.
      def enabled?
        S3Bucket.any_enabled?
      end

      def s3_url?(url)
        url.to_s.start_with?(SCHEME)
      end
   end

    # INSTANCE METHODS -----------

    def initialize
      @bucket = S3Bucket.primary
    end
    
    def key_prefix(s3_bucket)
      prefix ||= s3_bucket.key_prefix.delete_prefix("/")
      return "" if prefix.empty?
      prefix.end_with?("/") ? prefix : "#{prefix}/"
    end


    # Memoized per configuration, so changing a setting takes effect
    # without a restart.
    def client(s3_bucket)
      config = client_config(s3_bucket)
      if @client.nil? || @client_config != config
        @client_config = config
        @client = Aws::S3::Client.new(**config)
      end
      @client
    end

    # --- key / path / url conversions ---------------------------------------

    # "archives/bookmarks/<id>/f.mp3" (or absolute under Rails.root) → key
    def key_for_local_path(local_path, s3_bucket=@bucket)
      relative = local_path.to_s.delete_prefix(Rails.root.to_s).delete_prefix("/")
      relative = relative.delete_prefix("#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/")
      "#{key_prefix(s3_bucket)}#{relative}"
    end

    # "/archives/bookmarks/<id>/f.mp3" → key
    def key_for_web_path(web_path, s3_bucket=@bucket)
      key_for_local_path(web_path.to_s.delete_prefix("/"), s3_bucket)
    end

    # "s3://bucket_name/key" → key (nil when the url isn't ours)
    def key_for_s3_url(url, s3_bucket=@bucket)
      return nil unless self.class.s3_url?(url)
      rest = url.to_s.delete_prefix(SCHEME)
      url_bucket, key = rest.split("/", 2)
      return nil if url_bucket != s3_bucket.name || key.blank?
      key
    end

    # Accepts a web path, local path or s3 url.
    def key_for(url_or_path, s3_bucket=@bucket)
      return key_for_s3_url(url_or_path, s3_bucket) if self.class.s3_url?(url_or_path)
      return key_for_web_path(url_or_path, s3_bucket) if url_or_path.to_s.start_with?("/")
      key_for_local_path(url_or_path, s3_bucket)
    end

    # Like remote_storage_has? but for a path without an extension:
    # returns the web path of the first object whose key starts with it.
    #
    # @return [String, nil]
    def web_path_for_path_prefix(local_path_prefix, s3_bucket=@bucket)
      key = first_key_with_prefix(
        key_for_local_path(local_path_prefix, s3_bucket),
        s3_bucket
      )
      key ? web_path_for_key(key, s3_bucket) : nil
    end
    
    def web_path_for_key(key)
      "/#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/#{key.to_s.delete_prefix(key_prefix)}"
    end

    def web_path_for_s3_url(url, s3_bucket=@bucket)
      key = key_for_s3_url(url, s3_bucket)
      key ? web_path_for_key(key, s3_bucket) : nil
    end

    def s3_url_for_key(key, s3_bucket)
      "#{SCHEME}#{s3_bucket.name}/#{key}"
    end

    def s3_url_for_web_path(web_path, s3_bucket=@bucket)
      s3_url_for_key(key_for_web_path(web_path, s3_bucket))
    end

    # --- remote operations --------------------------------------------------

    # upload a copy of the specified file to each enabled bucket
    def upload_local_file(local_file_path, content_type: nil)
      S3Bucket.enabled_buckets.each do | s3_bucket |
        key = key_for_local_path(local_file_path, s3_bucket)
        upload(local_file_path, key, s3_bucket, content_type: content_type)
      end
    end
    
    # Uploads a local file. Content-Type is derived from the extension so
    # browsers render images / play audio from the presigned URL.
    # Tests if the file already exists in each enabled bucket before
    # uploading
    def upload(local_path, key, s3_bucket, content_type: nil)
      # don't upload it if it's already there
      return true if exists?(key, s3_bucket)
      content_type ||= Rack::Mime.mime_type(File.extname(local_path), "application/octet-stream")
      File.open(local_path, "rb") do |io|
        client(s3_bucket).put_object(bucket: s3_bucket.name, key: key, body: io, content_type: content_type)
      end
      true
    end

    # @return [Aws::S3::Types::HeadObjectOutput, nil]
    def head(key, s3_bucket)
      client(s3_bucket).head_object(bucket: s3_bucket.name, key: key)
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      nil
    end


    # tests if the specified key exists in the specified bucket
    # defaults to testing if it exists in the primary primary
    def exists?(key, s3_bucket=@bucket)
      return false unless s3_bucket
      !head(key, s3_bucket).nil?
    end

    # First key under +prefix+, or nil. Used when the extension of an archived
    # asset isn't known up front (see Archiver#download_asset).
    def first_key_with_prefix(prefix, s3_bucket=@bucket)
      client(s3_bucket).list_objects_v2(
        bucket: s3_bucket.name,
        prefix: prefix,
        max_keys: 1
      ).contents.first&.key
    end
    

    def download(key, to_path, s3_bucket=@bucket)
      FileUtils.mkdir_p(File.dirname(to_path))
      client(s3_bucket).get_object(bucket: s3_bucket.name, key: key, response_target: to_path)
      to_path
    end

    def delete_url(url, s3_bucket=@s3_bucket)
      S3Bucket.enabled_buckets.each do | s3_bucket |
        key = key_for(url, s3_bucket)
        next unless key.present?
        client(s3_bucket).delete_object(bucket: s3_bucket.name, key: key)
      end
      true
    end

    # Deletes every object under a "folder". +prefix+ must end with "/" so a
    # bookmark id can't match a sibling that merely starts the same way.
    #
    # @return [Integer] number of objects deleted
    #                   Note: if there are multiple enabled buckets
    #                         there will be one count for each copy
    #                         deleted in every bucket
    def delete_prefix(prefix)
      raise ArgumentError, "prefix must end with /" unless prefix.to_s.end_with?("/")
      deleted = 0
      S3Bucket.enabled_buckets.each do | s3_bucket |
        continuation_token = nil
        current_client = client(s3_bucket)
        loop do
          page = current_client.list_objects_v2(
            bucket:             s3_bucket.name,
            prefix:             prefix,
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
      end
      deleted
    end

    def presigned_url(key, s3_bucket: @bucket)
      Aws::S3::Presigner.new(client: client(s3_bucket))
        .presigned_url(
          :get_object,
          bucket:     s3_bucket.name,
          key:        key,
          expires_in: s3_bucket.presigned_url_expiry
        )
    end

    private

    def client_config(s3_bucket)
      # note: endpoint may be nil in the case of AWS
      endpoint = s3_bucket.endpoint.to_s
      config = {
        region: s3_bucket.region,
        access_key_id: s3_bucket.access_key_id,
        secret_access_key: s3_bucket.secret_access_key,
        force_path_style: s3_bucket.force_path_style != false
      }
      config[:endpoint] = endpoint if endpoint.present?
      config
    end
  end
end
