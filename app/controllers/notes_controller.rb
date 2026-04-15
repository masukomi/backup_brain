class NotesController < ApplicationController
  before_action :authenticate_user!, only: %i[new create edit update destroy]
  before_action :set_note, only: %i[show edit update destroy]
  before_action :set_limit, only: %i[index tagged_with]
  before_action :set_page, only: %i[index tagged_with]

  def index
    query = Note.all.order_by([[:updated_at, :desc]])
    query = apply_tag_filter(params[:tags], query)
    query = privatize(query)
    @tags_list = query.pluck(:tags).flatten.sort.uniq
      .map { |t| helpers.decode_entities(t) }
    @pagy, @notes = pagify(query)
  end

  def tagged_with
    @query_tags = params[:tags].split(",")
    if @query_tags.blank?
      flash_message(:notice, t("tags.errors.no_tags_provided"))
      redirect_to notes_url
      return
    end

    visible = privatize(
      Note.tagged_with_all(@query_tags).order_by([[:updated_at, :desc]])
    )
    @tags_list = visible.pluck(:tags).flatten.sort.uniq
      .map { |t| helpers.decode_entities(t) }
    @pagy, @notes = pagify(visible)
    render :index
  end

  def show
  end

  def new
    @note = Note.new
  end

  def edit
  end

  def create
    @note = Note.new(note_params)
    if @note.save
      redirect_to @note, notice: t("notes.creation_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @note.update(note_params)
      redirect_to @note, notice: t("notes.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @note.destroy
    redirect_to notes_url, notice: t("notes.deletion_success")
  end

  private

  def set_note
    @note = Note.find(params[:id])
    if @note.private && !user_signed_in?
      flash_message(:error, t("accounts.access_denied"))
      redirect_to notes_url
    end
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to notes_url
  end

  def privatize(query)
    user_signed_in? ? query : query.where(private: false)
  end

  def apply_tag_filter(tags, query)
    if tags.present?
      @query_tags = tags.split(",")
      query = query.tagged_with_all(@query_tags)
    end
    query
  end

  def note_params
    raw = params.require(:note).permit(:string_data, :private, :sensitive, :tags)
    tags = Tag.split_tags(raw[:tags] || "")
    raw.merge(tags: tags)
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
end
