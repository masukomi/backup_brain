class Transcription
  include Mongoid::Document
  include Mongoid::Timestamps

  # The stem of the archived audio filename (a SHA256 digest of the source URL).
  # Used as the deduplication key — the same audio file always produces the same hash
  # regardless of which bookmark or archive references it.
  field :source_hash,   type: String

  # Relative web path to the archived audio file,
  # e.g. /archives/bookmarks/<bookmark_id>/abc123def.mp3
  field :source_path,   type: String

  field :bookmark_id,   type: BSON::ObjectId
  field :text,          type: String
  field :status,        type: String, default: "pending"  # pending / processing / completed / failed
  field :error,         type: String
  field :whisper_model, type: String
  field :source,        type: String  # "youtube" or "whisper"

  index({source_hash: 1, bookmark_id: 1}, {unique: true})
  index({bookmark_id: 1})
end
