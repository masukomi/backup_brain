module BookmarksHelper
  def show_archive_link(archive)
    link_to(
      archive.created_at.strftime("%Y-%m-d"),
      bookmark_path(archive.bookmark, archive_id: archive._id.to_s)
    )
  end
end
