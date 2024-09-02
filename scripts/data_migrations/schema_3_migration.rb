require "paint"
schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 2
  puts "Beginning migration to schema_version 3"

  oauth2_client_id = Setting.where(lookup_key: "oauth2_client_id").first
  if !oauth2_client_id
    require "securerandom"

    uuid = SecureRandom.uuid

    # there shouldn't be one
    Setting.create!(
      lookup_key: "oauth2_client_id",
      summary: "a unique oauth2 client id for this Backup Brain installation",
      description: "Used when communicating with OAuth authenticated servers",
      visible: false,
      value: uuid
    )
    puts Paint["✅ New OAuth2 Client ID generated", :green]
  else
    warn Paint["an OAuth2 Client ID already exists.", :yellow]
  end
  oauth2_client_secret = Setting.where(lookup_key: "oauth2_client_secret").first
  if !oauth2_client_secret
    require "securerandom"

    secret = SecureRandom.hex(32)

    # there shouldn't be one
    Setting.create!(
      lookup_key: "oauth2_client_secret",
      summary: "a unique oauth2 client secret for this Backup Brain installation",
      description: "Used when communicating with OAuth authenticated servers",
      visible: false,
      value: secret
    )
    puts Paint["✅ New OAuth2 Client Secret generated", :green]
  else
    warn Paint["an OAuth2 Client Secret already exists.", :yellow]
  end

  schema_version_setting.value = 3
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 3", :green]

  else
    warn Paint["⚠️  Unable to update schema_version setting to 3", :red]
    exit 70 # EX_SOFTWARE (70) An internal software error has been detected.
  end

end
exit 0 # no need to do anything
