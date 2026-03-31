class YouTubeTranscriptionJob < ApplicationJob
  queue_as :low_priority

  def self.enabled?
    ENV["ENABLE_YOUTUBE_TRANSCRIPTIONS"] == "true"
  end

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param video_id [String] the YouTube video ID
  # @param archive_id [String, nil] the Archive's BSON ObjectId as a string; when
  #   provided the Transcription's id is pushed into that Archive's transcription_ids
  def perform(bookmark_id:, video_id:, archive_id: nil)
    unless self.class.enabled?
      Rails.logger.warn("YouTubeTranscriptionJob: ENABLE_YOUTUBE_TRANSCRIPTIONS is not set to 'true', skipping")
      return false
    end

    bookmark_bson = BSON::ObjectId.from_string(bookmark_id.to_s)

    existing = Transcription.where(source_hash: video_id, bookmark_id: bookmark_bson).first
    if existing && %w[pending failed].exclude?(existing.status)
      Rails.logger.info("YouTubeTranscriptionJob: #{video_id} already has status '#{existing.status}', skipping")
      link_transcription_to_archive(existing._id, archive_id, bookmark_bson)
      return existing.status == "completed"
    end

    transcription = existing || Transcription.new(
      source_hash: video_id,
      source_path: "https://www.youtube.com/watch?v=#{video_id}",
      bookmark_id: bookmark_bson,
      source: "youtube"
    )
    transcription.status = "processing"
    transcription.save!

    begin
      fetched_transcript = YoutubeRb::Transcript::YouTubeTranscriptApi.new.fetch(video_id)
      text = fetched_transcript.snippets.map { |s| "#{sprintf "%-12s", s.start.to_s} #{s.text}" }.join("\n")
      transcription.update!(status: "completed", text: text, error: nil)
      link_transcription_to_archive(transcription._id, archive_id, bookmark_bson)
      Rails.logger.info("YouTubeTranscriptionJob: completed for #{video_id}")
      true
    rescue => e
      Rails.logger.warn("YouTubeTranscriptionJob: failed for #{video_id} - #{e.message}")
      transcription.update!(status: "failed", error: e.message)
      false
    end
  end

  private

  def link_transcription_to_archive(transcription_id, archive_id, bookmark_bson)
    return unless archive_id
    bookmark = Bookmark.find(bookmark_bson)
    archive  = bookmark.archives.find(BSON::ObjectId.from_string(archive_id.to_s))
    return unless archive
    return if archive.transcription_ids.include?(transcription_id)
    archive.transcription_ids << transcription_id
    bookmark.save!
  rescue => e
    Rails.logger.warn("YouTubeTranscriptionJob: failed to link transcription to archive #{archive_id}: #{e.message}")
  end
end
