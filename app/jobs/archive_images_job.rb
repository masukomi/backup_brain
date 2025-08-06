require "uri"
require "tempfile"
require "open3"
require "digest"

class ArchiveImagesJob < ArchiveUrlJob
  MAX_THREAD_COUNT = 10
  # NOTE: to find all the bookmarks with archive
  # that contain image links use the regexp from
  # Bookmark.where(archives: {"$elemMatch" => {string_data: ArchiveUrlJob::IMAGE_MD_LINK_REGEXP}}).count
  #

  queue_as :low_priority # :default

  # @param bookmark [String|NilClass|BSON::ObjectId::Mongoid::Criteria]
  #        Pass in a single bookmark id to archive images for just that bookmark,
  #        or NilClass to archive images on all bookmarks that don't already have archived images.
  # @param skip_those_with_archived_images [TrueClass|FalseClass]
  #        if true this will ignore any bookmark where
  #        has_archived_images? returns true
  #        This would indicate we've already done the work.
  #        Only set to false if you've deleted archives created
  #        after image archiving was added.
  # @param skip_recent [FalseClass|Numeric]  If you pass in a number
  #        it will skip processing any archive created
  #        since that many minutes ago.
  def perform(bookmarks:,
    skip_those_with_archived_images: true,
    skip_recent: false)
    bookmark_ids = []
    if bookmarks.blank?
      bookmark_ids = if skip_recent
        Rails.logger.info("XXX skipping ALL recently archived")
        Bookmark.only_archived_before_ids(minutes_ago: skip_recent)
      else
        Bookmark.archived.pluck(:_id)
      end
    elsif bookmarks.is_a? Mongoid::Criteria
      bookmark_ids = bookmarks.pluck(:_id)
    elsif bookmarks.is_a? Array
      bookmark_ids = bookmarks
      if bookmarks.first.is_a? Bookmark
        bookmark_ids = bookmark_ids.map { |b| b._id }
      end
    elsif bookmarks.is_a? Bookmark
      bookmark_ids = [bookmark._id]
    elsif bookmark.is_a? String
      bookmark_ids = [bookmark]
    else
      raise TypeError.new("Unsupported input type")
    end

    bookmark_ids.delete(nil) # never trust user input

    Rails.logger.debug "#{bookmark_ids.size} bookmarks to process…"
    queue = Queue.new
    bookmark_ids.each { |e| queue << e }
    threads = []
    num_threads = (bookmark_ids.size > 100) ? MAX_THREAD_COUNT : 1
    Rails.logger.info("Launching #{num_threads} Thread(s) to download images from archives")
    (1..num_threads).each do |n|
      threads << Thread.new do
        while (id = begin
          queue.pop(true)
        rescue
          nil
        end)
          Rails.logger.info "Thread #{n}: archiving images for bookmark: #{id}"
          process_bookmark(bookmark_id: id,
            skip_those_with_archived_images: skip_those_with_archived_images,
            skip_recent: skip_recent)
          Rails.logger.info "Thread #{n}: #{queue.length} bookmarks remaining in queue to archive images"
        end
      end
    end

    threads.each { |t| t.join }
  end

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def process_bookmark(bookmark_id:,
    skip_those_with_archived_images:,
    skip_recent:)
    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    return false unless bookmark
    if skip_those_with_archived_images && bookmark.has_archived_images?
      Rails.logger.warn("Bookmark already has archived images. #{bookmark_id}")
      return true
    end

    if bookmark.unarchived?
      Rails.logger.warn("Asked to archive images for UNarchived bookmark: #{bookmark_id}")
      return false
    end

    latest_archive = bookmark.latest_archive("text/markdown")
    return false unless latest_archive

    if skip_recent.is_a? Numeric
      if latest_archive.created_since?(minutes_ago: skip_recent)
        timestamp = latest_archive.created_at.strftime("%Y/%m/%d %H:%M %p")
        Rails.logger.warn("XXX skipping recent archive: #{timestamp}")
      end
    end

    begin
      markdown = latest_archive.string_data
      updated_markdown = fully_qualify_urls(markdown, bookmark)

      # if the strings match then either
      # - there were no images to archive
      # - none of them were archivable
      # - we already archived them
      # in which case, it's silly to create a new archive
      return bookmark if updated_markdown == markdown

      bookmark.archives << Archive.new(
        mime_type: "text/markdown",
        string_data: updated_markdown
      )
      bookmark.save!
    rescue BackupBrain::Errors::UnarchivableUrl => e
      Rails.logger.error(e.message)
      begin
        tempfile.close
      rescue
        nil
      end
      nil
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ETIMEDOUT
    # 599 Network Connect Timeout Error
    record_failed_attempt(bookmark, 599, should_raise: false)
  rescue => e
    Rails.logger.warn("couldn't re-archive images #{bookmark.url} - #{e.message}")

    nil
  end

  # Unlike ArchiveUrlJob this _only_ touches image links.
  # Since we're working on an existing archive it's assumed that
  # all the text links have already been fully qualified.
  #
  # @return line with fully qualified image links
  def process_md_links(bookmark, line, domain, directory)
    line, image_url_hashes = Archive.extract_image_links_from_line(line)
    return line if image_url_hashes.empty?

    qualify_and_apply_image_url_hashes(bookmark, image_url_hashes, line.dup, domain, directory)
  end
end
