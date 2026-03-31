require "paint"

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 4
  puts "Beginning migration to schema_version 5"

  # Archive gained two new fields:
  #   transcription_ids (Array, default: [])
  #   hero_image_path   (String, no default — nil when absent)
  #
  # Use MongoDB array filters to update only the embedded archive sub-documents
  # that are missing each field, without loading every Bookmark into Ruby.

  result = Bookmark.collection.update_many(
    {"archives" => {"$elemMatch" => {"transcription_ids" => {"$exists" => false}}}},
    {"$set" => {"archives.$[elem].transcription_ids" => []}},
    array_filters: [{"elem.transcription_ids" => {"$exists" => false}}]
  )
  puts Paint["✅ Set transcription_ids: [] on archives in #{result.modified_count} bookmark(s)", :green]

  result = Bookmark.collection.update_many(
    {"archives" => {"$elemMatch" => {"hero_image_path" => {"$exists" => false}}}},
    {"$set" => {"archives.$[elem].hero_image_path" => nil}},
    array_filters: [{"elem.hero_image_path" => {"$exists" => false}}]
  )
  puts Paint["✅ Set hero_image_path: nil on archives in #{result.modified_count} bookmark(s)", :green]

  schema_version_setting.value = 5
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 5", :green]
  else
    warn Paint["⚠️  Unable to update schema_version setting to 5", :red]
    exit 70 # EX_SOFTWARE
  end
end
exit 0
