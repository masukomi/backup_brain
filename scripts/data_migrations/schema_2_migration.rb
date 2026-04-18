require "paint"
def guarantee_existing_tag_quality
  puts Paint["ℹ️ Checking for & cleaning any potentially invalid tags", :yellow]
  counter = 0
  Bookmark.all.each do |b|
    cleaned_tags = Tag.split_tags(b.tags.join(" "))
    if cleaned_tags != b.tags
      b.tags = cleaned_tags
      b.save
      counter += 1
    end
  end
  puts Paint["✅ Tag cleaning complete. #{counter} Bookmarks needed updating.", :green]
end

schema_version = begin
  Setting.get_value_of_key("schema_version")
rescue BackupBrain::Errors::UnknownSetting
  1 # it's ok, we'll make one.
end

if schema_version == 1
  puts "Beginning migration to schema_version 2"
  guarantee_existing_tag_quality
  Tag.regenerate_all!
  schema_version_setting ||= Setting.new(
    lookup_key: "schema_version",
    summary: "Database Schema Version",
    description: "Used by the upgrade scripts to perform data migrations as database schemas change over time",
    visible: false
  )
  schema_version_setting.set_value_and_type(2)
  schema_version_setting.save!

  favicon_setting = Setting.where(lookup_key: "enable_favicons").first
  if !favicon_setting

    favicon_setting = Setting.new(
      lookup_key: "enable_favicons",
      summary: "Allow Backup Brain to pull favicons from Google",
      description: "When enabled Backup Brain will request favicons for the domain names you have bookmarked, and display them alongside the bookmark. ",
      visible: true
    )
    favicon_setting.set_value_and_type(true)
    favicon_setting.save!
    puts Paint["✅ Favicon setting added & enabled.", :green]
  else
    puts Paint["✅ won't touch existing Favicon setting.", :green]
  end
  puts Paint["✅ Migration to schema_version 2 complete", :green]
elsif schema_version > 1
  warn Paint["⚠️ schema_version doesn't indicate migration for schema_version 2 is applicable", :yellow]
  exit 0 # no need to do anything
end
