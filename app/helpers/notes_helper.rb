module NotesHelper
  # rubocop:disable Rails/HelperInstanceVariable
  def get_pagination_links_for_notes_query(pagy:, query:, limit:, tags:)
    joined_tags = get_joined_tags(tags)
    path_for = proc { |page_num|
      notes_search_path(page: page_num,
        limit: limit,
        query: query,
        tags: joined_tags)
    }

    link = proc { |page_num, _link_extra|
      link_to(
        page_num,
        path_for.call(page_num),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }

    {
      link_proc: link,
      previous_link: link_to(
        t("pagination.previous"),
        path_for.call(pagy.prev),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_previous")
      ),
      next_link: link_to(
        t("pagination.next"),
        path_for.call(pagy.next),
        method: :get,
        class: "page-link",
        aria_label: I18n.t("pagination.aria_next")
      )
    }
  end

  def get_pagination_links_for_notes(pagy:, limit:, tags:)
    joined_tags = tags&.join(",") || ""
    if @query_tags.present?
      notes_tagged_with_path(tags: joined_tags.presence || @query_tags.join(","))
    else
      notes_path
    end

    link = proc { |page_num, _link_extra|
      path = if @query_tags.present?
        notes_tagged_with_path(page: page_num, limit: limit, tags: joined_tags.presence || @query_tags.join(","))
      else
        notes_path(page: page_num, limit: limit)
      end
      link_to(page_num, path, method: :get, class: "page-link",
        aria_label: I18n.t("pagination.aria_next"))
    }

    previous_path = if @query_tags.present?
      notes_tagged_with_path(page: pagy.prev, limit: limit, tags: joined_tags.presence || @query_tags.join(","))
    else
      notes_path(page: pagy.prev, limit: limit)
    end

    next_path = if @query_tags.present?
      notes_tagged_with_path(page: pagy.next, limit: limit, tags: joined_tags.presence || @query_tags.join(","))
    else
      notes_path(page: pagy.next, limit: limit)
    end

    {
      link_proc: link,
      previous_link: link_to(t("pagination.previous"), previous_path, method: :get,
        class: "page-link", aria_label: I18n.t("pagination.aria_previous")),
      next_link: link_to(t("pagination.next"), next_path, method: :get,
        class: "page-link", aria_label: I18n.t("pagination.aria_next"))
    }
  end
  # rubocop:enable Rails/HelperInstanceVariable
end
