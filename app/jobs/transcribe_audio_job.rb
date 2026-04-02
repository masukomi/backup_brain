class TranscribeAudioJob < ApplicationJob
  queue_as :low_priority

  # @param bookmark_id [String] the bookmark's BSON ObjectId as a string
  # @param audio_local_path [String] web-relative path to the archived audio file,
  #   e.g. "/archives/bookmarks/<id>/abc123def.mp3"
  # @param archive_id [String] the Archive's BSON ObjectId as a string
  # @param media_object_id [String] the MediaObject's BSON ObjectId as a string
  def perform(bookmark_id:, audio_local_path:, archive_id:, media_object_id:)
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path, archive_id: archive_id, media_object_id: media_object_id)
  end

  def transcribe_now(audio_local_path:, bookmark_id: nil, archive_id: nil, media_object_id: nil)
    if bookmark_id.nil?
      match = audio_local_path.match(/bookmarks\/(?<bookmark_id>[0-9a-f]{24,})\//)
      return false unless match
      bookmark_id = match[:bookmark_id]
    end
    core_perform(bookmark_id: bookmark_id, audio_local_path: audio_local_path, archive_id: archive_id, media_object_id: media_object_id)
  end

  def core_perform(bookmark_id:, audio_local_path:, archive_id:, media_object_id:)
    unless BackupBrain::WhisperClient.enabled?
      Rails.logger.warn("TranscribeAudioJob: enable_audio_transcriptions setting is false, skipping")
      return false
    end

    model_path = begin
      Setting.get_value_of_key("whisper_model_path").to_s.strip
    rescue BackupBrain::Errors::UnknownSetting
      ""
    end
    if model_path.empty?
      Rails.logger.warn("TranscribeAudioJob: whisper_model_path setting is not set, skipping")
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

    fs_path = Rails.root.join(audio_local_path.delete_prefix("/")).to_s
    unless File.exist?(fs_path)
      Rails.logger.warn("TranscribeAudioJob: file not found: #{audio_local_path}")
      return false
    end

    bookmark = Bookmark.find(_id: bookmark_id.to_s)
    archive = bookmark.archives.find(_id: archive_id.to_s)
    media_object = archive.media_objects.find(_id: media_object_id.to_s)

    transcription = media_object.build_processing_transcription(
      bookmark_id: bookmark_id,
      model_path: model_path
    )
    bookmark.save!

    begin
      transcription.text = whisper.transcribe(fs_path)
      transcription.status = "completed"
      transcription.error = nil
      bookmark.save!
      Rails.logger.info("TranscribeAudioJob: completed for #{File.basename(audio_local_path, ".*")}")
      true
    rescue => e
      Rails.logger.warn("TranscribeAudioJob: failed for #{audio_local_path} - #{e.message}")
      transcription.status = "failed"
      transcription.error = e.message
      bookmark.save!
      false
    end
  end
end
