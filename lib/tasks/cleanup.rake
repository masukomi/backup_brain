require "paint"
require "whirly"
require "ruby-progressbar"

namespace :cleanup do
  # defaults to true if response code is ambiguous

  def cleanup_task_rearchive(mongoid_criteria)
    counter = 0
    skip_counter = 0
    fail_counter = 0
    Whirly.configure spinner: "dots"
    Whirly.start do
      mongoid_criteria.each do |bookmark|
        title = bookmark.title
        title = title[0..25] + "…" if title.length > 25
        url = bookmark.url
        url = url[0..25] + "…" if url.length > 25

        # there's no point in wasting our time trying to download
        # pages from sites that no longer exist, or don't want
        # to let us download them
        if bookmark.failed_archive_attempts.size >= 3
          skip_counter += 1
          puts Paint["Skipping: #{title} @ #{url}", :yellow]
          next
        end

        # if you've archived some, and need to rerun this and skip them
        # update the date to be just before you last ran this
        # next if bookmark.archives.size > 0 && bookmark.archives.last.created_at > DateTime.parse("08 Jul 2024 00:00:00")
        counter += 1

        Whirly.status = Paint["Re-archiving: #{title} @ #{url}", :green]
        begin
          # returns a Bookmark or nil, or throws an exception
          result = bookmark.generate_archive(true)
          unless result&.is_a? Bookmark
            fail_counter += 1
            # Whirly.status = Paint["Failed to rearchive: #{title} @ #{url}", :red]
            puts Paint["Failed to rearchive: #{title} @ #{url}", :red]
          end
        rescue
          fail_counter += 1
          # Whirly.status = Paint["Failed to rearchive: #{title} @ #{url}", :red]
          puts Paint["Failed to rearchive: #{title} @ #{url}", :red]
        end
      end
    end
    puts "Archived #{counter} bookmarks"
    if skip_counter > 0
      puts "⚠️ Skipped #{skip_counter} bookmarks that already had 3+ failed archive attempts.
You can attempt a manual archiving of these if you want,
but it probably won't work."
    end
    puts "⚠️ Failed to archive #{fail_counter} bookmarks." if fail_counter > 0
  end
  desc "Reindexes all bookmarks"
  task reindex_all: [:environment] do
    puts "Reindexing has begun, and will continue in the background."
    puts "This may take a little while to finish."
    puts "Feel free to close this window."
    Bookmark.reindex # asynchronous
    # if you try and run the synchronous one (.reindex!)
    # it'll probably time out if you have lots of bookmarks.
  end

  desc "Retry unarchived bookmarks"
  task retry_unarchived: [:environment] do
    cleanup_task_rearchive(Bookmark.unarchived)
  end

  desc "Rearchive all bookmarks"
  task rearchive_all: [:environment] do
    cleanup_task_rearchive(Bookmark.all)
  end

  desc "Regenerate Transcripts"
  task regenerate_transcripts: [:environment] do
    begin
      Transcription.destroy_all
    rescue
      nil
    end # for legacy data structure

    bar = ProgressBar.create(
      total: Bookmark.where(:archives.exists => true).count,
      format: "%t |%B| %c/%C  %E  elapsed: %a",
      title: "Skills",
      output: $stdout,
      projector: {type: "smoothing", strength: 0.5}
    )

    videos_queued = 0
    audios_queued = 0
    content_cleaned = 0
    Bookmark.where(:archives.exists => true).each do |b|
      my_archive = b.archives.last
      next unless my_archive # can't happen
      if my_archive.string_data.blank?
        message = "Invalid archive: Bookmark id: '#{b.id}' Archive id: #{my_archive.id}"
        bar.log Paint["  #{message}", :red]
        Rails.logger.error(message)
        next
      end

      my_archive.media_objects.destroy_all
      modified = false
      my_archive.audio_urls.each do |url|
        bar.log Paint["  Queueing audio #{url}", :gray]
        my_archive.add_media_object(url, simple_type: "audio")
        audios_queued += 1
        modified = true
      end

      my_archive.video_urls.each do |url|
        bar.log Paint["  Queueing video #{url}", :gray]
        my_archive.add_media_object(url, simple_type: "video")
        videos_queued += 1
        modified = true
      end

      if b.url.to_s.match(BackupBrain::YouTube::URL_REGEXP)
        my_archive.add_media_object(url, simple_type: "video")
        modified = true
      end

      # imported mastodon bookmarks may have embedded youtube BS at their end
      if b.tags.include?("mastodon_bookmark")
        lines = my_archive.string_data.split(/\r\n|\n/)
        # find_index {|item| block}
        the_bad_one = lines.find_index { |line| line.include?("<iframe") }
        if the_bad_one
          bar.log Paint["  stripping iframe from #{b.title}…", :yellow]
          my_archive.string_data = lines.slice(0..(the_bad_one - 1))
          content_cleaned += 1
          modified = true
        end
      end
      b.save! if modified
      bar.increment
    end
    bar.finish
  end

  desc "Fetch YouTube transcripts for bookmarks that don't have one yet"
  task gather_yt_transcripts: [:environment] do
    youtube_url_re = /https?:\/\/(?:www\.|m\.)?(?:youtube\.com\/watch\?|youtu\.be\/)/

    direct = Bookmark.where(url: youtube_url_re).to_a
    mastodon = Bookmark.where(tags: FetchMastodonBookmarksJob::MASTODON_TAG).select do |b|
      b.latest_archive&.string_data&.match?(BackupBrain::YouTube::URL_REGEXP)
    end

    all = (direct + mastodon).uniq(&:id)
    puts "Found #{all.size} bookmark(s) with YouTube content"

    done_counter = 0
    skip_counter = 0
    fail_counter = 0

    all.each_with_index do |bookmark, i|
      archive = bookmark.latest_archive

      unless archive
        skip_counter += 1
        next
      end

      if archive.transcription_ids.present?
        puts Paint["[#{i + 1}/#{all.size}] Skipping — already has transcript: #{bookmark.url}", :yellow]
        skip_counter += 1
        next
      end

      video_ids = if (vid = BackupBrain::YouTube.video_id(bookmark.url))
        [vid]
      else
        archive.string_data.scan(BackupBrain::YouTube::URL_REGEXP).pluck(0).uniq
      end

      video_ids.each do |video_id|
        puts Paint["[#{i + 1}/#{all.size}] Fetching transcript: #{bookmark.url}", :green]
        puts "\t⎣#{bookmark.title.nil? ? "NO TITLE" : bookmark.title}"
        begin
          YouTubeTranscriptionJob.perform_now(
            bookmark_id: bookmark._id.to_s,
            video_id: video_id,
            archive_id: archive._id.to_s
          )
          done_counter += 1
        rescue => e
          fail_counter += 1
          puts Paint["[#{i + 1}/#{all.size}] Failed: #{e.message}", :red]
        end
      end

      sleep 2
    end

    puts "Fetched #{done_counter} transcript(s)"
    puts Paint["Skipped #{skip_counter} bookmark(s)", :yellow] if skip_counter > 0
    puts Paint["Failed #{fail_counter} bookmark(s)", :red] if fail_counter > 0
  end

  desc "Destroy useless bookmarks"
  task destroy_useless_bookmarks: [:environment] do
    unarchived = Bookmark
      .or(
        {:archives.exists => false},
        {archives: {"$size": 0}}
      )

    counter = 0
    # Whirly.configure spinner: "dots"
    # Whirly.start do
    unarchived.each do |bookmark|
      # try to archive it
      # if it fails, destroy it
      # Whirly.status = "checking: #{bookmark.title} @ #{bookmark.url}"
      puts "checking: #{bookmark.title} @ #{bookmark.url}"
      success = begin
        bookmark.generate_archive(true)
      rescue
        false
      end

      if !success
        counter += 1
        # Whirly.status = Paint["destroying: #{bookmark.title} @ #{bookmark.url}", :yellow]
        puts Paint["destroying: #{bookmark.title} @ #{bookmark.url}", :yellow]
        #  code = HTTParty.head(bookmark.url).response.code.to_i
        bookmark.destroy
      end
    end
    # end
    if counter > 0
      puts "Deleted #{counter} useless bookmarks. So sad. 😭"
    else
      puts "Wow. No useless URLs found! Amazing!"
    end
  end
end
