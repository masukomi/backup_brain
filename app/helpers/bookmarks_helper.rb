module BookmarksHelper
  def is_fresh?(bookmark)
    bookmark.created_at > 2.minutes.ago
  end

  def show_archive_link(archive)
    link_to(
      archive_date_string(archive),
      bookmark_path(archive.bookmark, archive_id: archive._id.to_s)
    )
  end

  def archive_date_string(archive)
    I18n.l(archive.created_at.to_date, format: :default)
  end
end
