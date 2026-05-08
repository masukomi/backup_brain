class ReviewsController < ApplicationController
  before_action :authenticate_user!, only: %i[new create edit update destroy]
  before_action :set_review, only: %i[show edit update destroy]
  before_action :set_limit, only: %i[index tagged_with]
  before_action :set_page, only: %i[index tagged_with]

  def index
    query = Review.all.order_by([[:updated_at, :desc]])
    query = apply_tag_filter(params[:tags], query)
    query = privatize(query)
    @tags_list = query.pluck(:tags).flatten.sort.uniq
      .map { |t| helpers.decode_entities(t) }
    @pagy, @reviews = pagify(query)
  end

  def tagged_with
    @query_tags = params[:tags].split(",")
    if @query_tags.blank?
      flash_message(:notice, t("tags.errors.no_tags_provided"))
      redirect_to reviews_url
      return
    end

    visible = privatize(
      Review.tagged_with_all(@query_tags).order_by([[:updated_at, :desc]])
    )
    @tags_list = visible.pluck(:tags).flatten.sort.uniq
      .map { |t| helpers.decode_entities(t) }
    @pagy, @reviews = pagify(visible)
    render :index
  end

  def show
  end

  def new
    @review = Review.new
  end

  def edit
  end

  def create
    @review = Review.new(review_params)
    if @review.save
      redirect_to @review, notice: t("reviews.creation_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @review.update(review_params)
      redirect_to @review, notice: t("reviews.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @review.destroy
    redirect_to reviews_url, notice: t("reviews.deletion_success")
  end

  private

  def set_review
    @review = Review.find(params[:id])
    if @review.private && !user_signed_in?
      flash_message(:error, t("accounts.access_denied"))
      redirect_to reviews_url
    end
  rescue Mongoid::Errors::DocumentNotFound
    redirect_to reviews_url
  end

  def privatize(query)
    if user_signed_in? && cookies[:hide_private].blank?
      query
    else
      query.where(private: false)
    end
  end

  def apply_tag_filter(tags, query)
    if tags.present?
      @query_tags = tags.split(",")
      query = query.tagged_with_all(@query_tags)
    end
    query
  end

  def review_params
    raw = params.require(:review).permit(:title, :string_data, :rating, :private, :sensitive, :tags)
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
