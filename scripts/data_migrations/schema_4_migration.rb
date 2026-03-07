require "paint"
schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 3
  puts "Beginning migration to schema_version 4"
  # load the new mastodon OauthSiteType data
  Rails.application.load_seed

end
exit 0 # no need to do anything
