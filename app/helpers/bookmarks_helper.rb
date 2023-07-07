module BookmarksHelper
  def show_archive_link(archive, bookmark)
    link_to(
      archive.created_at.strftime("%Y-%m-d"),
      bookmark_path(bookmark, archive_id: archive._id.to_s)
    )
  end
end
