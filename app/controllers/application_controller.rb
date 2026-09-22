class ApplicationController < ActionController::Base
  include Pagy::Backend
  include BackupBrain::Grouping
  include ApiKeyAuthenticatable
  VALID_ALTERNATE_LAYOUTS = %w[application webextension]
  # raw formats return every match rather than a page.
  # 10k is Meilisearch's practical ceiling, and what the
  # tags-sidebar query already uses.
  RAW_RESULT_CAP = 10_000
  layout :get_layout

  before_action :set_layout
  before_action :set_user_count
  before_action :configure_permitted_devise_params, if: :devise_controller?

  def flash_message(type, text)
    generic_flash_message(flash, type, text)
  end

  def inline_flash_message(type, text)
    generic_flash_message((@inline_flash ||= {}), type, text)
  end

  protected

  def generic_flash_message(hash, type, text)
    hash[type] ||= []
    if text.present? && hash[type].exclude?(text)
      # was accidentally getting duplicate hash messages
      hash[type] << text
    end
  end

  def get_layout
    if params[:layout].present? && VALID_ALTERNATE_LAYOUTS.include?(params[:layout])
      params[:layout]
    else
      "application"
    end
  end

  def set_layout
    @layout = get_layout
  end

  def set_user_count
    @user_count = User.count
  end

  def configure_permitted_devise_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
  end

  def central_search(search_for:)
    @search_for = search_for
    klass = (search_for == :bookmarks) ? Bookmark : Note
    @query = params[:query]
    @query, @query_tags = Tag.extract_tags_from_string(@query)

    if params[:tags].present?
      @query_tags += params[:tags].split(",")
    end

    if @query.blank?
      # a script can't follow a flash message, so raw callers get
      # a real error instead of a redirect
      if raw_format?
        render_api_error(:bad_request, t("search.missing_query"))
      elsif @query_tags.present?
        redirect_to action: "tagged_with", tags: @query_tags.join(",")
      else
        flash_message(:notice, t("search.missing_query"))
        redirect_to action: "index"
      end
      return
    end

    # configure sorting
    sort_params = []
    @sort = params[:sort] || "match"
    if @sort == "newest"
      sort_params << "created_at:desc"
    end

    # Meilisearch Options
    # raw formats aren't paginated: they get everything, up to the cap
    options = if raw_format?
      {limit: RAW_RESULT_CAP, sort: sort_params, offset: 0}
    else
      {
        limit: @limit,
        sort: sort_params,
        offset: (@limit * (@page - 1)) # number of resources skipped
      }
    end
    unless include_private_records?
      options[:filter] = "private = false"
    end

    if @query_tags.present?
      options = add_tags_to_search_options(@query_tags, options)
    end

    if search_for == :notes
      # notes have no archives, so there's nothing to opt in to searching
      @search_archives = false
      options[:attributes_to_search_on] = Note::QUERYABLE_ATTRIBUTES
    else
      @search_archives = params[:search_archives] == "true"
      unless @search_archives
        options[:attributes_to_search_on] = %w[title description tags url]
      end
    end

    # Separate options for fetching ALL matching IDs across all pages (for tags sidebar).
    # In raw mode the main query already IS that query, so we skip the second search.
    all_ids_options = options.except(:limit, :offset).merge(limit: RAW_RESULT_CAP)

    begin
      # if we were searching for _any_ record we'd use `filtered_by_class: false`
      # note: already privatized via filter
      # raw_results is a hash see the following for details
      # https://github.com/masukomi/mongodb_meilisearch?tab=readme-ov-file#searching
      raw_results = klass.search(@query,
        options: options,
        ids_only: true,
        filtered_by_class: true)
      all_ids_results = if raw_format?
        raw_results
      else
        klass.search(@query,
          options: all_ids_options,
          ids_only: true,
          filtered_by_class: true)
      end

      results = klass.where(:id.in => raw_results["matches"])
      if @query_tags&.present?
        # in theory, this is redundant because the search criteria
        # would have filtered on tags BUT I'd rather be sure
        results = results.tagged_with_all(@query_tags)
      end
      if search_for == :notes
        @notes = results
      else
        @bookmarks = results
      end

      all_matching = klass.where(:id.in => all_ids_results["matches"])
      all_matching = all_matching.tagged_with_all(@query_tags) if @query_tags&.present?
      @tags_list = all_matching.pluck(:tags).flatten.sort.uniq
      if search_for == :notes
        @tags_list = @tags_list.map { |t| helpers.decode_entities(t) }
      end
      # raw formats aren't paginated, so there's nothing to page through
      @pagy = pagify_search(raw_results["search_result_metadata"]["nbHits"]) unless raw_format?

      respond_to do |format|
        format.html { render :index }
        format.json { render :search }
        format.md   { render :search, formats: [:md], layout: false }
      end
    rescue MeiliSearch::ApiError => e
      if raw_format?
        render_api_error(:bad_gateway, t("api.errors.search_unavailable", error: e.message))
      elsif e.message.include?("Index `#{klass.search_index_name}` not found")
        if klass.count > 0
          flash_message(:notice, t("search.missing_index"))
        else
          flash_message(:notice,
            (search_for == :notes) ? t("search.no_notes") : t("search.no_bookmarks"))
        end
      elsif e.message.include?("The provided API key is invalid")
        search_key = ENV.fetch("MEILISEARCH_SEARCH_KEY", nil)
        admin_key = ENV.fetch("MEILISEARCH_ADMIN_KEY", nil)
        if search_key.present? && admin_key.present?
          flash_message(:error, t("search.invalid_api_key"))
        else
          flash_message(:error, t("search.invalid_master_api_key"))
        end
      else
        flash_message(:error, t("search.unknown_error", error: e.message))
      end
      redirect_to((search_for == :notes) ? notes_path : bookmarks_path) unless raw_format?
    end
  end

  # A valid API key belongs to the (single) owner of this instance,
  # so it sees everything. Otherwise fall back to the session rules.
  def include_private_records?
    return true if current_api_key.present?
    user_signed_in? && cookies[:hide_private].blank?
  end

  # adds tags to the search options being passed to Meilisearch
  #
  # Documentation on the query we're building
  # can be found here:
  # https://www.meilisearch.com/docs/learn/filtering_and_sorting/filter_expression_reference#in
  #
  def add_tags_to_search_options(tags, options)
    options[:filter] ||= ""

    if tags.size > 0
      options[:filter] += " AND " if options[:filter].present?
      options[:filter] += "tags IN [#{tags.join(", ")}]"
    end

    options
  end

  def pagify(query, page = @page, limit = @limit)
    paginated_query = query.paginate(page: page, limit: limit)
    [
      Pagy.new(count: query.count, page: page, items: limit),
      paginated_query
    ]
  end

  def pagify_search(count, page = @page, limit = @limit)
    Pagy.new(count: count, page: page, items: limit)
  end
end
