class FailedArchiveAttempt
  include Mongoid::Document
  include Mongoid::Timestamps
  field :status_code, type: Integer
  embedded_in :bookmark
end
