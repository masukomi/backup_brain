# run me via the rails console or rails runner.
# finds all the MediaObject records that either
# don't have a transcription OR whose
# attempt at transcription failed with errors.

retranscribe_count = 0

Bookmark.all.each do |bookmark|
  bookmark.archives.each do |archive|
    archive.media_objects.each do |mo|
      has_error = mo.transcription.present? && mo.transcription.error.present?
      missing   = mo.transcription.nil?

      next unless has_error || missing

      if mo.transcription.present?
        mo.transcription.destroy
      end

      mo.save
      mo.transcribe
      retranscribe_count += 1
    end
  end
end

puts "Queued #{retranscribe_count} media objects for re-transcription"
