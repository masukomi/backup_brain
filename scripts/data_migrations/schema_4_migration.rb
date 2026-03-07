require "paint"
schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 3
  puts "Beginning migration to schema_version 4"
  # load the new mastodon OauthSiteType data
  Rails.application.load_seed

  schema_version_setting.value = 4
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 4", :green]

  else
    warn Paint["⚠️  Unable to update schema_version setting to 4", :red]
    exit 70 # EX_SOFTWARE (70) An internal software error has been detected.
  end
end
exit 0 # no need to do anything
