class YouTubeTranscriptionJob < ApplicationJob
  queue_as :low_priority

  def self.enabled?
    ENV["ENABLE_YOUTUBE_TRANSCRIPTIONS"] == "true"
  end

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param video_id [String] the YouTube video ID
  # @param archive_id [String] the Archive's BSON ObjectId as a string
  # @param media_object_id [String] the MediaObject's BSON ObjectId as a string
  def perform(bookmark_id:, video_id:, archive_id:, media_object_id:)
    unless self.class.enabled?
      Rails.logger.warn("YouTubeTranscriptionJob: ENABLE_YOUTUBE_TRANSCRIPTIONS is not set to 'true', skipping")
      return false
    end

    bookmark = Bookmark.find(_id: bookmark_id.to_s)
    archive = bookmark.archives.find(_id: archive_id.to_s)
    media_object = archive.media_objects.find(_id: media_object_id.to_s)

    transcription = media_object.build_processing_transcription(bookmark_id: bookmark_id)
    bookmark.save!

    begin
      fetched_transcript = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(video_id)
      transcription.text = fetched_transcript.snippets.map { |s| "#{sprintf "%-12s", s.start.to_s} #{s.text}" }.join("\n")
      transcription.status = "completed"
      transcription.error = nil
      bookmark.save!
      Rails.logger.info("YouTubeTranscriptionJob: completed for #{video_id}")
      true
    rescue => e
      Rails.logger.warn("YouTubeTranscriptionJob: failed for #{video_id} - #{e.message}")
      transcription.status = "failed"
      transcription.error = e.message
      bookmark.save!
      false
    end
  end
end
