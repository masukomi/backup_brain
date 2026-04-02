OauthSiteType.find_or_create_by!(slug: "mastodon") do |t|
  t.name                  = "Mastodon"
  t.slug                  = "mastodon"
  t.description           = "Connect to any Mastodon instance"
  t.registration_strategy = "mastodon_v1_apps"
  t.registration_path     = "/api/v1/apps"
  t.authorization_path    = "/oauth/authorize"
  t.token_path            = "/oauth/token"
  t.default_scopes        = ["read"]
end

# Audio Transcriptions Settings
if Setting.where(lookup_key: "enable_audio_transcriptions").count == 0
  whisper_model_path_lookup_key = "whisper_model_path"
  warn("creating #{whisper_model_path_lookup_key} setting")
  if Setting.where(lookup_key: whisper_model_path_lookup_key).count == 0
    Setting.create!(
      {
        lookup_key: whisper_model_path_lookup_key,
        summary: "File path to a downloaded Whisper Model",
        description: "A valid path to a downloaded whisper model

  Path can be absolute or relative to the root of this app.
  Must be a readable whisper model file.
  ",
        visible: true,
        value_type: :string,
        value: {value: "whisper-models/ggml-large-v3-turbo-q5_0.bin"}
      }
    )
  end

  warn("creating enable_audio_transcriptions setting")
  setting = Setting.create!(
    {
      lookup_key: "enable_audio_transcriptions",
      summary: "Whisper transcriptions of audio files.",
      description: "Whisper must be installed and available on your path for this to work.

Before enabling this, download a whisper model and set its file path in the
whisper_model_path setting.
",
      visible: true,
      value_type: :boolean,
      value: {value: false}
    }
  )
  warn("creating enable_audio_transcriptions setting path dependency")
  sd = SettingDependency.new(
    dependency_lookup_key: whisper_model_path_lookup_key,
    name: "Whisper Model Path",
    notes: "must be a valid path to a whisper model",
    test: <<~RUBY
      BackupBrain::WhisperClient.instance.viable?
    RUBY

  )
  setting.setting_dependencies << sd
  setting.save!

  warn("Please add a valid Whisper Model Path in Settings if you wish to enable Audio Transcriptions")
end

# oAuth Settings
if Setting.where(lookup_key: "oauth2_client_secret").count == 0
  warn("creating oauth2_client_secret setting")

  require "securerandom"
  secret = SecureRandom.hex(32)
  Setting.create!(
    lookup_key: "oauth2_client_secret",
    summary: "a unique oauth2 client secret for this Backup Brain installation",
    description: "Used when communicating with OAuth authenticated servers",
    visible: false,
    value_type: :string,
    value: {value: secret}
  )
end

oauth2_client_id = Setting.where(lookup_key: "oauth2_client_id").first
if !oauth2_client_id
  warn("creating oauth2_client_id setting")
  require "securerandom"
  uuid = SecureRandom.uuid

  # there shouldn't be one
  Setting.create!(
    lookup_key: "oauth2_client_id",
    summary: "a unique oauth2 client id for this Backup Brain installation",
    description: "Used when communicating with OAuth authenticated servers",
    visible: false,
    value_type: :string,
    value: {value: uuid}
  )
end

if Setting.where(lookup_key: "enable_youtube_transcriptions").count == 0
  warn("creating enable_youtube_transcriptions setting")
  Setting.create!(
    {
      lookup_key: "enable_youtube_transcriptions",
      summary: "downloads transcripts for YouTube videos",
      description: "Uses the YouTube API to download the transcript from any public video.",
      visible: true,
      value_type: :boolean,
      value: {value: true}
    }
  )
end

# reader_path setting ─────────────────────────────
if Setting.where(lookup_key: "reader_path").count == 0
  warn("creating reader_path setting")

  Setting.create!(
    {
      lookup_key: "reader_path",
      summary: "path to reader executable",
      description: "The path to the reader executable.
This can be an absolute path or relative to the root of
this project.",
      visible: true,
      value_type: :string,
      value: {value: "bin/reader"}
    }
  )
end

# enable_archiving setting ─────────────────────────────
if Setting.where(lookup_key: "enable_archiving").count == 0
  warn("creating enable_archiving setting")

  enable_archiving_setting = Setting.create!(
    {
      lookup_key: "enable_archiving",
      summary: "creates archives of each bookmark",
      description: "Uses various tools to extract the important content from
bookmarked web pages and converts them to markdown.

The reader cli tool must be installed and
its path must be configured in the reader_path setting.",
      visible: true,
      value_type: :boolean,
      value: {value: false}
    }
  )
  enable_archiving_dep_1 = SettingDependency.new(
    dependency_lookup_key: "reader_path",
    name: "reader_path_dependency",
    notes: "tests that the reader_path setting has a valid path",
    test: <<~RUBY
      BackupBrain::ArchiveTools.valid_reader_path?
    RUBY
  )
  enable_archiving_setting.setting_dependencies << enable_archiving_dep_1
  enable_archiving_setting.save!
end
