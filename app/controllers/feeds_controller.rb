class FeedsController < ApplicationController
  def audio
    @secret_key = params[:secret_key]
    @valid_secret_key = @secret_key.present? && SecretKey.is_valid?(@secret_key)

    bookmarks = Bookmark.archived.order_by(created_at: :desc)
    bookmarks = bookmarks.where(private: false) unless @valid_secret_key

    @bookmarks = bookmarks.to_a.select do |b|
      b.sorted_archives.first&.media_objects&.any? { |mo| mo.simple_type == "audio" }
    end
    @bookmarks = @bookmarks.first(params[:max_records].to_i) if params[:max_records].present?

    respond_to do |format|
      format.rss { render layout: false }
    end
  end

  def to_read
    @secret_key = params[:secret_key]
    @valid_secret_key = @secret_key.present? && SecretKey.is_valid?(@secret_key)

    bookmarks = Bookmark.to_read.archived.order_by(created_at: :desc)
    bookmarks = bookmarks.where(private: false) unless @valid_secret_key
    bookmarks = bookmarks.limit(params[:max_records].to_i) if params[:max_records].present?
    @bookmarks = bookmarks.to_a

    respond_to do |format|
      format.rss { render layout: false }
    end
  end
end
