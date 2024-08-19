class BookmarksController < ApplicationController
  # ⚠ WARNING TO FUTUTRE HACKERS
  # The user privacy stuff in here is based on the idea that
  # there will only be one user.
  # It is guaranteed to expose private data if
  # you allow multiple accounts to be created.
  # Don't do that. This is a single-user instance.

  before_action :set_bookmark, only: %i[show download edit update archive destroy]
  before_action :set_limit, only: %i[index tagged_with search unarchived to_read]
  before_action :set_page, only: %i[index tagged_with search unarchived to_read]
  before_action :set_closeable, only: %i[new edit create update show]
  before_action :set_archive, only: %i[show download]
  before_action :set_total_bookmarks, only: %i[index unarchived to_read tagged_with search]
  before_action :authenticate_user!, only: %i[new create update destroy archive mark_as_read mark_to_read]

  # GET /bookmarks or /bookmarks.json
  def index
    @tags_list = Tag.all
      .order_by([[:name, :asc]])
      .pluck(:name)
      .map { |t| helpers.decode_entities(t) }

    query = Bookmark.all.order_by([[:created_at, :desc]])
    if params[:tags].present?
      @tags = params[:tags].split(",")
      query = query.tagged_with_all(@tags)
    end
    query = privatize(query)

    @pagy, @bookmarks = pagify(query)
  end

  def unarchived
    query = Bookmark
      .or({:archives.exists => false}, {archives: {"$size": 0}})
      .order_by([[:created_at, :desc]])
    query = privatize(query)
    @pagy, @bookmarks = pagify(query)
    render :index
  end

  def to_read
    query = Bookmark.where(to_read: true)
      .order_by([[:created_at, :desc]])
    query = privatize(query)
    @pagy, @bookmarks = pagify(query)
    render :index
  end

  def tagged_with
    @tags = params[:tags].split(",")
    if @tags.blank?
      flash_message(:notice, t("tags.errors.no_tags_provided"))
      redirect_to :index
      return
    end

    tagged_with_criteria = Bookmark.tagged_with_all(@tags)
    @tags_list = tagged_with_criteria.pluck(:tags).flatten.sort.uniq
    @pagy, @bookmarks = pagify(
      privatize(
        tagged_with_criteria
        .order_by([[:created_at, :desc]])
      )
    )

    @tags_list = @tags_list.map { |t| helpers.decode_entities(t) }
    render :index
  end

  def search
    @query = params[:query]
    if @query.blank?
      flash_message(:notice, t("search.missing_query"))
      redirect_to action: "index"
      return
    end

    # configure sorting
    sort_params = []
    @sort = params[:sort] || "match"
    if @sort == "newest"
      sort_params << "created_at:desc"
    end

    # Meilisearch Options
    options = {
      limit: @limit,
      sort: sort_params,
      offset: (@limit * (@page - 1)) # number of resources skipped
    }
    unless user_signed_in?
      options[:filter] = "private = false"
    end

    if params[:tags].present?
      @tags = params[:tags].split(",")
      options = add_tags_to_search_options(@tags, options)
    end

    begin
      # if we were searching for _any_ record we'd use `filtered_by_class: false`
      # note: already privatized via filter
      # raw_results is a hash see the following for details
      # https://github.com/masukomi/mongodb_meilisearch?tab=readme-ov-file#searching
      raw_results = Bookmark.search(@query,
        options: options,
        ids_only: true,
        filtered_by_class: true)
      @bookmarks = Bookmark.where(:id.in => raw_results["matches"])
      if @tags&.present?
        # in theory, this is redundant because the search criteria
        # would have filtered on tags BUT I'd rather be sure
        @bookmarks = @bookmarks.tagged_with_all(@tags)
      end

      @tags_list = @bookmarks.pluck(:tags).flatten.sort.uniq
      @pagy      = pagify_search(raw_results["search_result_metadata"]["nbHits"])

      render :index
    rescue MeiliSearch::ApiError => e
      if e.message.include?("Index `backup_brain_general` not found")
        if Bookmark.count > 0
          flash_message(:notice, t("search.missing_index"))
        else
          flash_message(:notice, t("search.no_bookmarks"))
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
      redirect_to bookmarks_path
    end
  end

  # GET /bookmarks/1 or /bookmarks/1.json
  def show
    # set_archive is invoked before this
  end

  def download
    # set_archive is invoked before this
    mime_type = @archive.mime_type || "text/markdown"
    filename = (@bookmark.title || "bookmark")
      .downcase
      .gsub(/\W+/, "_")
      .sub(/_*$/, "") + ".md"
    send_data(@archive.string_data,
      type: mime_type,
      filename: filename,
      disposition: "attachment")
  end

  # GET /bookmarks/new
  def new
    if params[:url].present?
      @bookmark = Bookmark.where(url: params[:url]).first
    end
    if @bookmark.present?
      flash_message(:notice, t("bookmarks.create_existing_warning"))
      redirect_to edit_bookmark_url(@bookmark, layout: @layout, closeable: @closeable)
      return
    end
    url = params[:url].strip if params[:url].present?
    title = params[:title].strip if params[:title].present?
    description = params[:description].strip if params[:description].present?

    @bookmark = Bookmark.new(url: url, title: title, description: description)
  end

  # GET /bookmarks/1/edit
  def edit
  end

  # POST /bookmarks or /bookmarks.json
  def create
    @bookmark = Bookmark.new(split_tag_params)
    @bookmark.user = current_user

    respond_to do |format|
      if @bookmark.save
        format.html {
          flash_message(:notice, t("bookmarks.creation_success"))
          if @closeable.present?
            redirect_to bookmarks_success_path(layout: @layout, closeable: @closeable)
          else
            redirect_to bookmarks_path
          end
        }
        format.json { render :show, status: :created, location: @bookmark }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @bookmark.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT
  def archive
    updated_bookmark = @bookmark.generate_archive(true)
    @bookmark = updated_bookmark || @bookmark.reload

    respond_to do |format|
      format.turbo_stream {
        if updated_bookmark
          inline_flash_message(:notice, t("bookmarks.archiving_success"))
        else
          inline_flash_message(:error, t("bookmarks.archiving_error"))
        end
        render turbo_stream: turbo_stream.replace(
          @bookmark,
          partial: "bookmark",
          locals: {
            bookmark: @bookmark,
            inline_flash: @inline_flash
          }
        )
      }

      format.html {
        if updated_bookmark
          flash_message(:notice, t("bookmarks.archiving_success"))
        else
          flash_message(:error, t("bookmarks.archiving_error"))
        end
        redirect_to bookmark_url(@bookmark)
      }
    end
  end

  # PATCH/PUT
  def mark_as_read
    set_to_read(false)
  end

  # PATCH/PUT
  def mark_to_read
    set_to_read(true)
  end

  # PATCH/PUT /bookmarks/1 or /bookmarks/1.json
  def update
    respond_to do |format|
      # FIXME: there's got to be a better way to do this than my split_tag_params
      if @bookmark.update(split_tag_params)
        format.html {
          flash_message(:notice, t("bookmarks.update_success"))
          if @closeable.present?
            redirect_to bookmarks_success_path(layout: @layout, closeable: @closeable)
            # redirect_to bookmarks_success_path, layout: @layout
          else
            redirect_to bookmarks_path, notice: t("bookmarks.update_success")
          end
        }
        format.json { render :show, status: :ok, location: @bookmark }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @bookmark.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /bookmarks/1 or /bookmarks/1.json
  def destroy
    @bookmark.destroy

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          @bookmark,
          partial: "removed_bookmark",
          locals: {bookmark: @bookmark}
        )
      }
      format.html { redirect_to bookmarks_url, notice: t("bookmarks.deletion_success") }
      format.json { head :no_content }
    end
  end

  def success
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_bookmark
    @bookmark = Bookmark.find(params[:id])
    if @bookmark.private? && !user_signed_in?
      @bookmark = nil
      flash_message(:error, t("accounts.access_denied"))
      redirect_to bookmarks_url
    end
  end

  # Only allow a list of trusted parameters through.
  def bookmark_params
    params.require(:bookmark).permit(:title, :url, :description, :tags, :private, :to_read)
  end

  def split_tag_params
    unsplit_tags = params.dig(:bookmark, :tags)
    tags = Tag.split_tags(unsplit_tags)
    bookmark_params.merge({tags: tags})
  end

  def set_limit
    @limit = params[:limit].present? ? params[:limit].to_i : Pagy::DEFAULT[:items]
  end

  def set_page
    @page = params[:page].present? ? params[:page].to_i : 1
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

  # Indicates if the resulting window should close itself.
  def set_closeable
    # closeable comes in via new & edit,
    # then gets passed along to create and update
    # and finally to show, where the view will invoke it
    @closeable = params[:closeable].present? ? params[:closeable] == "true" : false
  end

  def set_total_bookmarks
    @total_bookmarks = Bookmark.count
  end

  def set_archive
    if @bookmark.blank?
      @archive = nil
      return
    end
    @archive = if params[:archive_id].blank?
      @bookmark.latest_archive("text/markdown")
    else
      @bookmark.archives.where(_id: params[:archive_id]).first
    end
  end

  def privatize(query)
    user_signed_in? ? query : query.where(private: false)
  end

  def set_to_read(to_read)
    @bookmark = Bookmark.find(params[:id])
    respond_to do |format|
      @bookmark.to_read = to_read
      if @bookmark.save
      else
        error = to_read ? t("bookmarks.mark_to_read_error") : t("bookmarks.mark_as_read_error")
        flash_message(:error, error) if error
      end
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          @bookmark,
          partial: "bookmark",
          locals: {bookmark: @bookmark}
        )
      }
    end
  end

  # adds tags to the search options being passed to Meilisearch
  #
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
end
