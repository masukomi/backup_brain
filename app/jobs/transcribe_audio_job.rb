class TranscribeAudioJob < ApplicationJob
  queue_as :low_priority

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param audio_local_path [String] web-relative path to the archived audio file,
  #   e.g. "/archives/bookmarks/<id>/abc123def.mp3"
  # @param archive_id [String, nil] the Archive's BSON ObjectId as a string; when
  #   provided the Transcription's id is pushed into that Archive's transcription_ids
  def perform(bookmark_id:, audio_local_path:, archive_id: nil)
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path, archive_id: archive_id)
  end

  def transcribe_now(audio_local_path:, bookmark_id: nil, archive_id: nil)
    if bookmark_id.nil?
      match = archive_local_path.match(/bookmarks\/(?<bookmark_id>[0-9a-f]{24,})\//)
      return false unless match
      if match
        bookmark_id = match[:bookmark_id]
      end
    end
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path, archive_id: archive_id)
  end

  def core_perform(bookmark_id:, audio_local_path:, archive_id: nil)
    unless BackupBrain::WhisperClient.enabled?
      Rails.logger.warn("TranscribeAudioJob: ENABLE_AUDIO_TRANSCRIPTIONS is not set to 'true', skipping")
      return false
    end

    model_path = ENV["WHISPER_MODEL_PATH"].to_s.strip
    if model_path.empty?
      Rails.logger.warn("TranscribeAudioJob: WHISPER_MODEL_PATH is not set, skipping")
      return false
    end

    resolved_model_path = Pathname.new(model_path).absolute? ? model_path : Rails.root.join(model_path).to_s
    unless File.readable?(resolved_model_path)
      Rails.logger.warn("TranscribeAudioJob: model file not readable at #{resolved_model_path}, skipping")
      return false
    end

    whisper = BackupBrain::WhisperClient.instance
    unless whisper.viable?
      Rails.logger.warn("TranscribeAudioJob: whisper not viable, skipping #{audio_local_path}")
      return false
    end

    source_hash   = File.basename(audio_local_path, ".*")
    bookmark_bson = BSON::ObjectId.from_string(bookmark_id.to_s)

    existing = Transcription.where(source_hash: source_hash, bookmark_id: bookmark_bson).first
    if existing && %w[pending failed].exclude?(existing.status)
      Rails.logger.info("TranscribeAudioJob: #{source_hash} has status '#{existing.status}', skipping")
      link_transcription_to_archive(existing._id, archive_id, bookmark_bson)
      return existing.status == "completed"
    end

    transcription = existing || Transcription.new(
      source_hash: source_hash,
      source_path: audio_local_path,
      bookmark_id: bookmark_bson,
      source: "whisper",
      whisper_model: File.basename(model_path)
    )
    transcription.status = "processing"
    transcription.save!

    fs_path = Rails.root.join(audio_local_path.delete_prefix("/")).to_s
    unless File.exist?(fs_path)
      transcription.update!(status: "failed", error: "Audio file not found at #{audio_local_path}")
      Rails.logger.warn("TranscribeAudioJob: file not found: #{audio_local_path}")
      return false
    end

    begin
      text = whisper.transcribe(fs_path)
      transcription.update!(status: "completed", text: text, error: nil)
      link_transcription_to_archive(transcription._id, archive_id, bookmark_bson)
      Rails.logger.info("TranscribeAudioJob: completed for #{source_hash}")
      true
    rescue => e
      Rails.logger.warn("TranscribeAudioJob: failed for #{audio_local_path} - #{e.message}")
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
    Rails.logger.warn("TranscribeAudioJob: failed to link transcription to archive #{archive_id}: #{e.message}")
  end
end
