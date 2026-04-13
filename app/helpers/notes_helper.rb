module NotesHelper
  # rubocop:disable Rails/HelperInstanceVariable
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
