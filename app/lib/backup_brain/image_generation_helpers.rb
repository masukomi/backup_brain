# lib/image_generation_helpers.rb

module BackupBrain
  module ImageGenerationHelpers
    def get_content_for_archive(archive)
      parts = [archive.string_data]
      transcript_texts = archive.media_objects
        .filter_map(&:transcription)
        .select { |t| t.status == "completed" }
        .map(&:text_without_timestamps)
      parts.concat(transcript_texts) if transcript_texts.any?
      parts.join("\n\n")
    end

    def store_image(bookmark, archive, image_data)
      filename = "#{Digest::SHA2.hexdigest(image_data)}.png"
      folder = guaranteed_archive_folder_path_for_doc(bookmark) # from ArchiveTools
      File.binwrite(File.join(folder, filename), image_data)
      archive.hero_image_path = "#{archive_web_path_for_doc(bookmark)}/#{filename}"
    end
  end
end
