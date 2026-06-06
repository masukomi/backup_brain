class ApiArchiveSource
  include Mongoid::Document
  include Mongoid::Timestamps

  field :remote_id, type: String
  field :service,   type: String

  belongs_to :oauth_site, optional: true
  embedded_in :bookmark

  validates :remote_id, :service, presence: true
end
