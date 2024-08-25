module BookmarksHelper
  def show_archive_link(archive)
    link_to(
      archive_date_string(archive),
      bookmark_path(archive.bookmark, archive_id: archive._id.to_s)
    )
  end

  def archive_date_string(archive)
    I18n.l(archive.created_at.to_date, format: :default)
  end

  def get_joined_tags(tags)
    tags.nil? ? "" : tags.join(",")
  end

  # TODO: there's a bunch of code below that can be
  # refactored into common methods

  def get_pagination_links_for_query(pagy:, query:, limit:, tags:)
    joined_tags = get_joined_tags(tags)
    link = proc { |pagy, link_extra|
      link_to(
        pagy,
        bookmarks_search_path(page: pagy,
          limit: limit,
          query: query,
          tags: joined_tags),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }

    previous_link = link_to(
      t("pagination.previous"),
      bookmarks_search_path(page: pagy.prev,
        limit: limit,
        query: query,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_previous")
    )
    next_link = link_to(
      t("pagination.next"),
      bookmarks_search_path(
        page: pagy.next,
        limit: limit,
        query: query,
        tags: joined_tags
      ),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_next")
    )
    {
      link_proc: link,
      previous_link: previous_link,
      next_link: next_link
    }
  end

  def get_pagination_links_for_unread(pagy:, limit:, tags:)
    joined_tags = get_joined_tags(tags)
    link = proc { |pagy, link_extra|
      link_to(
        pagy,
        bookmarks_to_read_path(page: pagy,
          limit: limit,
          tags: joined_tags),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }
    previous_link = link_to(
      t("pagination.previous"),
      bookmarks_to_read_path(page: pagy.prev,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_previous")
    )
    next_link = link_to(
      t("pagination.next"),
      bookmarks_to_read_path(page: pagy.next,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_next")
    )
    {
      link_proc: link,
      previous_link: previous_link,
      next_link: next_link
    }
  end

  def get_pagination_links_for_unarchived(pagy:, limit:, tags:)
    joined_tags = get_joined_tags(tags)
    link = proc { |pagy, link_extra|
      link_to(
        pagy,
        bookmarks_unarchived_path(page: pagy,
          limit: limit,
          tags: joined_tags),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }
    previous_link = link_to(
      t("pagination.previous"),
      bookmarks_unarchived_path(page: pagy.prev,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_previous")
    )
    next_link = link_to(
      t("pagination.next"),
      bookmarks_unarchived_path(page: pagy.next,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_next")
    )
    {
      link_proc: link,
      previous_link: previous_link,
      next_link: next_link
    }
  end

  def get_pagination_links_for_default(pagy:, limit:, tags:)
    joined_tags = get_joined_tags(tags)
    link = proc { |pagy, link_extra|
      link_to(
        pagy,
        bookmarks_path(page: pagy,
          limit: limit,
          tags: joined_tags),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }
    previous_link = link_to(
      t("pagination.previous"),
      bookmarks_path(page: pagy.prev,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_previous")
    )
    next_link = link_to(
      t("pagination.next"),
      bookmarks_path(page: pagy.next,
        limit: limit,
        tags: joined_tags),
      method: :get,
      class: "page-link",
      aria_label: I18n.t("pagination.aria_next")
    )
    {
      link_proc: link,
      previous_link: previous_link,
      next_link: next_link
    }
  end
end
