class Archive
  include Mongoid::Document
  include Mongoid::Timestamps
  field :mime_type,   type: String
  field :string_data, type: String

  embedded_in :bookmark
end
