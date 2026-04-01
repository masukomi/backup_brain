class TranscribeAudioJob < ApplicationJob
  queue_as :low_priority

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param audio_local_path [String] web-relative path to the archived audio file,
  #   e.g. "/archives/bookmarks/<id>/abc123def.mp3"
  # @param archive_id [String] the Archive's BSON ObjectId as a string; required —
  #   the Transcription is embedded in a MediaObject which is embedded in the Archive
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

    unless archive_id
      Rails.logger.warn("TranscribeAudioJob: archive_id is required to embed a MediaObject, skipping #{audio_local_path}")
      return false
    end

    fs_path = Rails.root.join(audio_local_path.delete_prefix("/")).to_s
    unless File.exist?(fs_path)
      Rails.logger.warn("TranscribeAudioJob: file not found: #{audio_local_path}")
      return false
    end

    source_hash   = File.basename(audio_local_path, ".*")
    bookmark      = Bookmark.find(_id: bookmark_id.to_s) # will error if invalid id
    archive       = bookmark.archives.find(_id: archive_id.to_s)

    mime          = Rack::Mime.mime_type(File.extname(audio_local_path).downcase, nil)
    media_object  = archive.media_objects.build(
      mime_type: mime,
      simple_type: "audio",
      url: audio_local_path
    )
    transcription = media_object.build_transcription(
      source_hash: source_hash,
      source_path: audio_local_path,
      bookmark_id: bookmark_bson,
      source: "whisper",
      whisper_model: File.basename(model_path),
      status: "processing"
    )

    # don't save the bookmark with the new objects unless we succed in transcribing

    begin
      transcription.text   = whisper.transcribe(fs_path)
      transcription.status = "completed"
      transcription.error  = nil
      bookmark.save!
      Rails.logger.info("TranscribeAudioJob: completed for #{source_hash}")
      true
    rescue => e
      Rails.logger.warn("TranscribeAudioJob: failed for #{audio_local_path} - #{e.message}")
      transcription.status = "failed"
      transcription.error  = e.message
      bookmark.save!
      false
    end
  end
end
