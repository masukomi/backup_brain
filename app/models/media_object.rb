class MediaObject
  include Mongoid::Document
  include Mongoid::Timestamps

  field :mime_type, type: String   # nil, or a valid "type/subtype" MIME string
  field :simple_type, type: String   # "audio" or "video"
  field :url, type: String   # relative archive path or http(s) URL
  field :hero_image_path, type: String
  field :alt_text, type: String

  embedded_in :archive
  embeds_one :transcription

  validates :url, presence: true
  validates :simple_type, presence: true, inclusion: {in: %w[audio video]}
  validates :mime_type, format: {with: /\A\w+\/[\w.+\-]+\z/}, allow_nil: true

  after_create :transcribe

  # Enqueues the appropriate transcription job for this media object.
  # Called automatically after_create. Safe to call manually to retry.
  def transcribe
    if simple_type == "video" && youtube_url?
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

  private

  def youtube_url?
    url&.match?(Archive::YOUTUBE_URL_REGEXP)
  end

  def extract_youtube_video_id
    m = url&.match(/(?:youtube\.com\/watch\?.*?v=|youtu\.be\/)([^&\s"'<>\)\[\]]+)/)
    m&.[](1)
  end
end
