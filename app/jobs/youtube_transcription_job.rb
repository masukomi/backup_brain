class YouTubeTranscriptionJob < ApplicationJob
  queue_as :low_priority

  def self.enabled?
    ENV["ENABLE_YOUTUBE_TRANSCRIPTIONS"] == "true"
  end

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param video_id [String] the YouTube video ID
  # @param archive_id [String] the Archive's BSON ObjectId as a string; required —
  #   the Transcription is embedded in a MediaObject which is embedded in the Archive
  def perform(bookmark_id:, video_id:, archive_id: nil)
    unless self.class.enabled?
      Rails.logger.warn("YouTubeTranscriptionJob: ENABLE_YOUTUBE_TRANSCRIPTIONS is not set to 'true', skipping")
      return false
    end

    unless archive_id
      Rails.logger.warn("YouTubeTranscriptionJob: archive_id is required to embed a MediaObject, skipping #{video_id}")
      return false
    end

    bookmark = Bookmark.find(_id: bookmark_id.to_s)
    archive  = bookmark.archives.find(_id: archive_id.to_s)

    youtube_url   = "https://www.youtube.com/watch?v=#{video_id}"
    media_object  = archive.media_objects.build(
      mime_type: nil,
      simple_type: "video",
      url: youtube_url,
      hero_image_path: archive.hero_image_path
    )
    bookmark.save!
    transcription = media_object.build_transcription(
      source_hash: video_id,
      source_path: youtube_url,
      bookmark_id: bookmark_bson,
      source: "youtube",
      status: "processing"
    )
    # don't save the bookmark with the new transcription unless we succed in transcribing

    begin
      fetched_transcript = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(video_id)
      transcription.text   = fetched_transcript.snippets.map { |s| "#{sprintf "%-12s", s.start.to_s} #{s.text}" }.join("\n")
      transcription.status = "completed"
      transcription.error  = nil
      bookmark.save!
      Rails.logger.info("YouTubeTranscriptionJob: completed for #{video_id}")
      true
    rescue => e
      Rails.logger.warn("YouTubeTranscriptionJob: failed for #{video_id} - #{e.message}")
      transcription.status = "failed"
      transcription.error  = e.message
      bookmark.save!
      false
    end
  end
end
