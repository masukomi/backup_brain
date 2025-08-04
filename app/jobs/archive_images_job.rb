require "uri"
require "tempfile"
require "open3"
require "digest"

class ArchiveImagesJob < ArchiveUrlJob
  THREAD_COUNT = 10
  # NOTE: to find all the bookmarks with archive
  # that contain image links use the regexp from
  # Bookmark.where(archives: {"$elemMatch" => {string_data: ArchiveUrlJob::IMAGE_MD_LINK_REGEXP}}).count
  #

  queue_as :low_priority # :default

  # @param bookmark [String|NilClass|BSON::ObjectId::Mongoid::Criteria] - Pass in a single bookmark id to archive images for just that bookmark,
  # or NilClass to archive images on all bookmarks that don't already have archived images.
  def perform(bookmarks:)
    bookmark_ids = []
    if bookmarks.blank?
      bookmark_ids = Bookmark.archived.pluck(:_id)
    elsif bookmarks.is_a? Mongoid::Criteria
      bookmark_ids = bookmarks.pluck(:_id)
    elsif bookmarks.is_a? Array
      bookmark_ids = bookmarks
    end

    bookmark_ids.delete(nil)

    bookmark_ids = Bookmark.archived.pluck(:_id)
    Rails.logger.debug "#{bookmark_ids.size} bookmarks to process…"
    queue = Queue.new
    bookmark_ids.each { |e| queue << e }
    threads = []
    THREAD_COUNT.times do
      threads << Thread.new do
        while (id = begin
          queue.pop(true)
        rescue
          nil
        end)
          Rails.logger.debug "processing bookmark: #{id}"
          process_bookmark(bookmark_id: id)
          Rails.logger.debug "#{queue.length} items remaining in queue to archive images of"
        end
      end
    end

    threads.each { |t| t.join }
  end

  # @return [Bookmark, nil] the bookmark if it was archived, nil if it wasn't
  def process_bookmark(bookmark_id:)
    bookmark = begin
      Bookmark.find(bookmark_id)
    rescue
      nil
    end
    return false unless bookmark
    if bookmark.has_archived_images?
      Rails.logger.warn("Bookmark already has archived images. #{bookmark_id}")
      return true
    end

    if bookmark.unarchived?
      Rails.logger.warn("Asked to archive images for UNarchived bookmark: #{bookmark_id}")
      return false
    end

    latest_archive = bookmark.latest_archive("text/markdown")
    return false unless latest_archive

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
  def process_md_links(bookmark, line, domain, directory)
    line, image_url_hashes = extract_image_links(line)
    return line if image_url_hashes.empty?

    new_line = line.dup

    image_url_hashes.each do |sha, url|
      full_url = fully_qualify_path(url, domain, directory)
      image_url_hashes[sha] = download_image(bookmark, full_url)
      new_line.sub!(sha, "![](#{image_url_hashes[sha]})")
    end

    new_line
  end
end
