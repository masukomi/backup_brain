require "paint"

# Settings created before groups existed (or by older seeds) all sit in the
# "default" group, so /settings shows one big "Default" accordion instead of
# Archiving / Transcription / Interface / … sections. Put each known setting
# in the group db/seeds.rb would give it today.
#
# Values are hardcoded on purpose: this must keep working on old databases
# long after the app's constants have moved on.

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if schema_version_setting&.inner_value == 7
  puts "Beginning migration to schema_version 8"

  groups = {
    "archiving" => %w[
      enable_archiving reader_path archival_requests_timeout
      missing_audio_audio_url missing_image_image_url
    ],
    "transcription" => %w[
      enable_audio_transcriptions whisper_model_path enable_youtube_transcriptions
    ],
    "generative_ai" => %w[
      gemini_api_key gemini_text_model gemini_image_model generate_audio_hero_images
      audio_transcript_image_prompt_guidance enable_local_ollama ollama_url ollama_model
    ],
    "interface" => %w[enable_favicons theme_names],
    "authentication" => %w[oauth2_client_secret oauth2_client_id indieauth_client_id_urls],
    "remote_storage" => %w[
      enable_s3_storage s3_endpoint s3_region s3_bucket s3_access_key_id
      s3_secret_access_key s3_key_prefix s3_force_path_style s3_presigned_url_expiry
    ],
    "internal" => %w[schema_version]
  }

  regrouped = 0
  groups.each do |group, lookup_keys|
    Setting.where(:lookup_key.in => lookup_keys).each do |setting|
      next if setting.group == group
      # `set` skips validations: old settings may fail today's dependency
      # checks, and that must not stop a cosmetic regrouping.
      setting.set(group: group)
      regrouped += 1
    end
  end
  puts Paint["✅ Moved #{regrouped} setting(s) into their groups", :green]

  leftovers = Setting.where(:lookup_key.nin => groups.values.flatten).pluck(:lookup_key)
  if leftovers.any?
    warn Paint["ℹ️  Left alone (unknown to this migration): #{leftovers.join(", ")}", :yellow]
  end

  schema_version_setting.set_value_and_type(8)
  if schema_version_setting.save
    puts Paint["✅ Updated schema_version setting to 8", :green]
  else
    warn Paint["⚠️  Unable to update schema_version setting to 8", :red]
    exit 70 # EX_SOFTWARE
  end
end
exit 0
