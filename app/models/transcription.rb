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

  embedded_in :media_object

  # Some Convenience methods to help find Transcriptions
  # since they're embedded in MediaObjects in Archives in Bookmarks
  # Bookmark → Archive(s) → MediaObject(s) → Transcription

  def self.get_count
    Bookmark.collection.aggregate([
      {"$unwind" => "$archives"},
      {"$unwind" => "$archives.media_objects"},
      {"$match" => {"archives.media_objects.transcription" => {"$exists" => true, "$ne" => nil}}},
      {"$count" => "total"}
    ]).first&.dig("total") || 0
  end

  def self.get_all
    Bookmark.collection.aggregate([
      {"$unwind" => "$archives"},
      {"$unwind" => "$archives.media_objects"},
      {
        "$match" => {
          "archives.media_objects.transcription" => {
            "$exists" => true, "$ne" => nil
          }
        }
      }
    ])
  end
end
