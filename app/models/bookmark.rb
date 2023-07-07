class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps

  after_create :generate_archive

  field :title,       type: String
  field :url,         type: String
  field :description, type: String
  field :tags,        type: Array

  embeds_many :archives

  validates :title, presence: true
  validates :url, presence: true
  validates :url, uniqueness: true

  def has_archive?
    archives.present?
  end

  def sorted_archives
    archives.order_by(created_at: -1)
  end

  def latest_archive(mime_type = nil)
    return nil unless has_archive?
    return sorted_archives.first if mime_type.nil?
    sorted_archives.where(mime_type: mime_type).first
  end

  def generate_archive
    raise t("errors.bookmarks.cant_archive_without_url") if url.blank?
    ArchiveUrlJob.perform_now(self)
  end
end
