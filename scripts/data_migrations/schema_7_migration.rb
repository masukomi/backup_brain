require "paint"

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 6
  puts "Beginning migration to schema_version 7"

  # Transcription gained a new field:
  #   source (String) — "youtube" or "whisper"
  #
  # Determine source by inspecting the associated bookmark:
  # - YouTube URL → "youtube"
  # - mastodon_bookmark tag → "youtube"
  # - anything else → "whisper"

  done   = 0
  failed = 0

  Transcription.all.each do |transcription|
    bookmark = Bookmark.find(transcription.bookmark_id)
    is_youtube = BackupBrain::YouTube.video_id(bookmark.url).present? ||
      bookmark.tags.include?(FetchMastodonBookmarksJob::MASTODON_TAG)
    transcription.update!(source: is_youtube ? "youtube" : "whisper")
    done += 1
  rescue => e
    failed += 1
    warn Paint["⚠️  Failed to update transcription #{transcription._id}: #{e.message}", :red]
  end

  puts Paint["✅ Updated source on #{done} transcription(s)", :green]
  warn Paint["⚠️  Failed to update #{failed} transcription(s)", :red] if failed > 0

  schema_version_setting.value = 7
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 7", :green]
  else
    warn Paint["⚠️  Unable to update schema_version setting to 7", :red]
    exit 70 # EX_SOFTWARE
  end
end
exit 0
