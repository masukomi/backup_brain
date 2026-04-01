class MediaObject
  include Mongoid::Document
  include Mongoid::Timestamps

  field :mime_type,       type: String   # nil, or a valid "type/subtype" MIME string
  field :simple_type,     type: String   # "audio" or "video"
  field :url,             type: String   # relative archive path or http(s) URL
  field :hero_image_path, type: String
  field :alt_text,        type: String

  embedded_in :archive
  embeds_one :transcription

  validates :url,         presence: true
  validates :simple_type, presence: true, inclusion: {in: %w[audio video]}
  validates :mime_type,   format: {with: /\A\w+\/[\w.+\-]+\z/}, allow_nil: true
end
