class BookmarksController < ApplicationController
  # ⚠ WARNING TO FUTUTRE HACKERS
  # The user privacy stuff in here is based on the idea that
  # there will only be one user.
  # It is guaranteed to expose private data if
  # you allow multiple accounts to be created.
  # Don't do that. This is a single-user instance.

  before_action :set_bookmark, only: %i[show edit update archive destroy]
  before_action :set_limit, only: %i[index tagged_with search unarchived to_read]
  before_action :set_page, only: %i[index tagged_with search unarchived to_read]
  before_action :set_closeable, only: %i[new edit create update show]
  before_action :set_total_bookmarks, only: %i[index unarchived to_read tagged_with search]
  before_action :authenticate_user!, only: %i[new create update destroy]

  # GET /bookmarks or /bookmarks.json
  def index
    query = privatize(Bookmark.all.order_by([[:created_at, :desc]]))

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
    @pagy, @bookmarks = pagify(
      privatize(Bookmark.where(tags: {"$in" => @tags})
        .order_by([[:created_at, :desc]])),
      items: @limit
    )
    render :index
  end

  def search
    @query = params[:query]
    if @query.blank?
      flash[:notice] = t("search.missing_query")
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

    # if we were searching for _any_ record we'd use `filtered_by_class: false`
    raw_results = privatize(Bookmark.search(@query, options: options, filtered_by_class: true))
    @pagy = pagify_search(raw_results["search_result_metadata"]["nbHits"])
    @bookmarks = raw_results["matches"]

    render :index
  end

  # GET /bookmarks/1 or /bookmarks/1.json
  def show
    # display with the most recent archive
    # TODO: handle the archive_id parameter
    @archive = if params[:archive_id].blank?
      @bookmark.latest_archive("text/markdown")
    else
      @bookmark.archives.where(_id: params[:archive_id])
    end
  end

  # GET /bookmarks/new
  def new
    if params[:url].present?
      @bookmark = Bookmark.where(url: params[:url]).first
    end
    if @bookmark.present?
      flash[:notice] = t("bookmarks.create_existing_warning")
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
          flash[:notice] = t("bookmarks.creation_success")
          if @closeable.present?
            redirect_to bookmarks_success_path(layout: @layout, closeable: @closeable)
          else
            redirect_to bookmark_url(@bookmark), notice: t("bookmarks.creation_success")
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
    if @bookmark.generate_archive
      flash[:notice] = t("bookmarks.archiving_success")
      redirect_to bookmark_url(@bookmark)
    else
      flash[:error] = t("bookmarks.archiving_error")
      redirect_back
    end
  end

  # PATCH/PUT /bookmarks/1 or /bookmarks/1.json
  def update
    respond_to do |format|
      # FIXME: there's got to be a better way to do this than my split_tag_params
      if @bookmark.update(split_tag_params)
        format.html {
          flash[:notice] = t("bookmarks.update_success")
          if @closeable.present?
            redirect_to bookmarks_success_path(layout: @layout, closeable: @closeable)
            # redirect_to bookmarks_success_path, layout: @layout
          else
            redirect_to edit_bookmark_url(@bookmark), notice: t("bookmarks.update_success")
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
      flash[:error] = t("accounts.access_denied")
      redirect_to bookmarks_url
    end
  end

  # Only allow a list of trusted parameters through.
  def bookmark_params
    params.require(:bookmark).permit(:title, :url, :description, :tags, :private, :to_read)
  end

  def split_tag_params
    tags = params[:tags].present? ? params[:tags].split(/\s+/) : []
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

  def privatize(query)
    user_signed_in? ? query : query.where(private: false)
  end
end
