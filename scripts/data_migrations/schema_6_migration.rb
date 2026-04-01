require "paint"

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 5
  puts "Beginning migration to schema_version 6"

  # Archives must have non-blank string_data. Any that slipped through without
  # content are invalid and should be removed.
  blank_string_data = {"$or" => [{"string_data" => nil}, {"string_data" => ""}]}

  affected = Bookmark.collection.count_documents(
    {"archives" => {"$elemMatch" => blank_string_data}}
  )
  puts Paint["  #{affected} bookmark(s) contain at least one blank archive", :yellow]

  result = Bookmark.collection.update_many(
    {"archives" => {"$elemMatch" => blank_string_data}},
    {"$pull" => {"archives" => blank_string_data}}
  )
  puts Paint["✅ Removed blank archives from #{result.modified_count} bookmark(s)", :green]

  schema_version_setting.value = 6
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 6", :green]
  else
    warn Paint["⚠️  Unable to update schema_version setting to 6", :red]
    exit 70
  end
end
exit 0
