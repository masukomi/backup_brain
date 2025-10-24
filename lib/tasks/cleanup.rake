require "paint"
require "whirly"

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
