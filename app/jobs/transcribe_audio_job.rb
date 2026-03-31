class TranscribeAudioJob < ApplicationJob
  queue_as :low_priority

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param audio_local_path [String] web-relative path to the archived audio file,
  #   e.g. "/archives/bookmarks/<id>/abc123def.mp3"
  def perform(bookmark_id:, audio_local_path:)
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path)
  end
  def transcribe_now(bookmark_id: nil, audio_local_path:)
    if bookmark_id.nil?
      match = archive_local_path.match(/bookmarks\/(?<bookmark_id>[0-9a-f]{24,})\//)
      return false unless match
      if match
        bookmark_id = match[:bookmark_id]
      end
    end
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path)
  end
  def core_perform(bookmark_id:, audio_local_path:)
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
    if existing && !%w[pending failed].include?(existing.status)
      Rails.logger.info("TranscribeAudioJob: #{source_hash} has status '#{existing.status}', skipping")
      return existing.status == "completed"
    end

    transcription = existing || Transcription.new(
      source_hash: source_hash,
      source_path: audio_local_path,
      bookmark_id: bookmark_bson,
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
      Rails.logger.info("TranscribeAudioJob: completed for #{source_hash}")
      true
    rescue => e
      Rails.logger.warn("TranscribeAudioJob: failed for #{audio_local_path} - #{e.message}")
      transcription.update!(status: "failed", error: e.message)
      false
    end
  end
end
