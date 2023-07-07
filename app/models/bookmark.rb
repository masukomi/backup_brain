class Bookmark
  include Mongoid::Document
  include Mongoid::Timestamps
  field :title,       type: String
  field :description, type: String
  field :tags,        type: Array

  embeds_many :archives


  def has_archive?
    archives.present?
  end

  def latest_archive(mime_type = nil)
    return nil unless has_archive?
    sorted = archives.order_by(create_at: -1)
    return sorted.first if mime_type.nil?
    sorted.where(mime_type: mime_type).first
  end

end
