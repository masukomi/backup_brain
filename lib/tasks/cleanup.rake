require "paint"
require "whirly"

namespace :cleanup do
  # defaults to true if response code is ambiguous

  desc "Reindexes all bookmarks"
  task reindex_all: [:environment] do
    # Puts we could just run Bookmark.reindex
    # but it's possible it'll timeout if you have
    # too many bookmarks. So we'll do it manually
    # Bookmark.reindex
    puts "Reindexing has begun. This may take a little while to finish."
    puts "Don't close this window until it's completed."
    Whirly.configure spinner: "dots"
    Whirly.start do
      Bookmark.all.each do |mark|
        mark.update_in_search
      end
    end
    puts "DONE REINDEXING"
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
