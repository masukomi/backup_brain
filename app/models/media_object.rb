class MediaObject
  include Mongoid::Document
  include Mongoid::Timestamps

  field :mime_type,       type: String   # nil, or a valid "type/subtype" MIME string
  field :simple_type,     type: String   # "audio" or "video"
  field :url,             type: String   # relative archive path or http(s) URL
  field :hero_image_path, type: String
  field :alt_text,        type: String
  field :sensitive,       type: Boolean, default: false

  embedded_in :archive
  embeds_one :transcription

  validates :url, presence: true
  validates :simple_type, presence: true, inclusion: {in: %w[audio video]}
  validates :mime_type, format: {with: /\A\w+\/[\w.+\-]+\z/}, allow_nil: true

  after_create :transcribe
  after_destroy :remove_remote_file

  # @return true if this is a video MediaObject with a YouTube url
  def is_youtube?
    simple_type == "video" && youtube_url?
  end

  # @return true if the media file lives in S3 (url is "s3://bucket/key")
  def stored_in_s3?
    BackupBrain::S3Storage.s3_url?(url)
  end

  # The path to hand to browsers and feed readers. Media in S3 is exposed
  # through its /archives/… path, which ArchivesController redirects to a
  # presigned URL. Anything else (local path, remote http url) is returned as-is.
  #
  # @return [String]
  def web_path
    return url unless stored_in_s3?
    BackupBrain::S3Storage.instance.web_path_for_s3_url(url) || url
  end

  # Enqueues the appropriate transcription job for this media object.
  # Called automatically after_create. Safe to call manually to retry.
  def transcribe
    # migrating old data we may and up attaching an existing Transcription
    # to a new MediaObject
    return if transcription.present? && transcription.error.blank?
    if transcription.present? # must have errored
      transcription.destroy
      save
    end
    if is_youtube?
      return unless YouTubeTranscriptionJob.enabled?
      video_id = extract_youtube_video_id
      return unless video_id
      YouTubeTranscriptionJob.perform_later(
        media_object_id: _id.to_s,
        bookmark_id: archive.bookmark._id.to_s,
        video_id: video_id,
        archive_id: archive._id.to_s
      )
    elsif simple_type == "audio"
      return unless BackupBrain::WhisperClient.enabled?
      TranscribeAudioJob.perform_later(
        media_object_id: _id.to_s,
        bookmark_id: archive.bookmark._id.to_s,
        audio_local_path: url,
        archive_id: archive._id.to_s
      )
    end
  end

  # Builds a Transcription in "processing" state on this MediaObject.
  # Used by TranscribeAudioJob and YouTubeTranscriptionJob.
  #
  # @param bookmark_id [String] BSON ObjectId string of the parent bookmark
  # @param model_path [String, nil] filesystem path to the Whisper model (audio only)
  # @return [Transcription]
  def build_processing_transcription(bookmark_id:, model_path: nil)
    attrs = {
      source_path: url,
      bookmark_id: BSON::ObjectId.from_string(bookmark_id.to_s),
      status: "processing"
    }
    if youtube_url?
      attrs[:source_hash] = extract_youtube_video_id
      attrs[:source] = "youtube"
    else
      attrs[:source_hash] = File.basename(url, ".*")
      attrs[:source] = "whisper"
      attrs[:whisper_model] = model_path ? File.basename(model_path) : nil
    end
    build_transcription(**attrs)
  end

  # Deletes this media's file from S3 once no other MediaObject on the same
  # bookmark refers to it. ArchivesController#modify dups MediaObjects into
  # each new Archive, so one file commonly backs several of them.
  def remove_remote_file
    return unless BackupBrain::S3Storage.enabled?
    return unless archived_file?
    return if other_media_objects_share_file?
    storage = BackupBrain::S3Storage.instance
    key = storage.key_for(url)
    storage.delete(key) if key.present?
  rescue => e
    Rails.logger.warn("MediaObject #{_id}: couldn't delete #{url} from S3 - #{e.message}")
  end

  private

  # true for files BackupBrain archived itself (local web path or s3 url),
  # false for remote media such as YouTube urls.
  def archived_file?
    stored_in_s3? || url.to_s.start_with?("/#{BackupBrain::ArchiveTools::ARCHIVES_FOLDER}/")
  end

  def other_media_objects_share_file?
    bookmark = archive&.bookmark
    return false unless bookmark
    bookmark.archives.any? do |other_archive|
      other_archive.media_objects.any? { |mo| mo._id != _id && mo.url == url }
    end
  end

  def youtube_url?
    url&.match?(Archive::YOUTUBE_URL_REGEXP)
  end

  def extract_youtube_video_id
    m = url&.match(/(?:youtube\.com\/watch\?.*?v=|youtu\.be\/)([^&\s"'<>\)\[\]]+)/)
    m&.[](1)
  end
end
