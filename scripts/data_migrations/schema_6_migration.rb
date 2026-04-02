require "paint"

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.value == 5 || schema_version_setting&.inner_value == 5
  puts "Beginning migration to schema_version 6"
  # feels like doing surgery on yourself to redefine the setting
  # enabled this to run.

  success = true
  begin
    oauth2_client_secret_setting = Setting.find_by(lookup_key: "oauth2_client_secret")
    if oauth2_client_secret_setting&.value&.is_a? String
      puts Paint["Updating oauth2_client_secret setting", :yellow]
      replacement_setting = oauth2_client_secret_setting.dup
      replacement_setting.value_type = :string
      replacement_setting.value = {value: oauth2_client_secret_setting.value}
      oauth2_client_secret_setting.destroy!
      replacement_setting.save!
    elsif oauth2_client_secret_setting
      puts Paint["✅ oauth2_client_secret setting is good to go", :green]
    else
      warn Paint["⚠️ oauth2_client_secret setting is missing", :red]
      success = false
    end

    enable_favicons_setting = Setting.find_by(lookup_key: "enable_favicons")
    if enable_favicons_setting&.value&.is_a?(TrueClass) || enable_favicons_setting&.value&.is_a?(TrueClass)
      puts Paint["Updating enable_favicons setting", :yellow]
      replacement_setting = enable_favicons_setting.dup
      replacement_setting.value_type = :boolean
      replacement_setting.value = {value: enable_favicons_setting.value}
      enable_favicons_setting.destroy!
      replacement_setting.save!
    elsif enable_favicons_setting
      puts Paint["✅ enable_favicons setting is good to go", :green]
    else
      warn Paint["⚠️ enable_favicons setting is missing", :red]
      success = false
    end

    oauth2_client_id_setting = Setting.find_by(lookup_key: "oauth2_client_id")
    if oauth2_client_id_setting&.value.is_a? String
      puts Paint["Updating oauth2_client_id setting", :yellow]
      replacement_setting = oauth2_client_id_setting.dup
      replacement_setting.value_type = :string
      replacement_setting.value = {value: oauth2_client_id_setting.value}
      oauth2_client_id_setting.destroy!
      replacement_setting.save!
    elsif oauth2_client_id_setting
      puts Paint["✅ oauth2_client_id setting is good to go", :green]
    else
      warn Paint["⚠️ oauth2_client_id setting is missing run `bundle exec rake db:seeds`", :red]
      warn Paint["XXX #{oauth2_client_id_setting.inspect}", :red]
      success = false
    end

    raise "Failed to update settings…" unless success

    schema_version_setting = Setting.find_by(lookup_key: "schema_version")
    if schema_version_setting&.value&.is_a? Integer
      puts Paint["Updating schema_version setting", :yellow]
      replacement_setting = schema_version_setting.dup
      replacement_setting.value_type = :integer
      replacement_setting.value = {value: 6}
      schema_version_setting.destroy!
      replacement_setting.save!
      puts Paint["✅ schema_version setting is good to go", :green]
    elsif schema_version_setting&.value&.is_a? Hash
      schema_version_setting.value[:value] = 6
      schema_version_setting.save!
    elsif schema_version_setting.nil?
      # how do you even compute bro?!
      warn Paint["⚠️ IMPOSSIBLE! schema_version setting is missing", :red]
      success = false
    end
  rescue StandardError => e

    warn Paint["⚠️  #{e.message}", :red]
    success = false
  end
  if success
    puts Paint["✅ Updated schema_version setting to 6", :green]
  else
    warn Paint["⚠️  Unable to update schema_version setting to 6", :red]
    exit 70 # EX_SOFTWARE
  end
end
exit 0
