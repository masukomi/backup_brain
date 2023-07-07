class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  field :title,       type: String, optional: false
  field :url,         type: String, optional: false
  field :description, type: String
  field :tags,        type: Array

  embeds_many :archives

  scope :sorted_archives, -> { order_by(created_at: -1) }

  def has_archive?
    archives.present?
  end

  def latest_archive(mime_type = nil)
    return nil unless has_archive?
    return sorted_archives.first if mime_type.nil?
    sorted_archives.where(mime_type: mime_type).first
  end

  def generate_archive
    raise t("errors.bookmarks.cant_archive_without_url") if url.blank?
  end
end
