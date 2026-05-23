OauthSiteType.find_or_create_by!(slug: "bookwyrm") do |t|
  t.name = "BookWyrm"
  t.slug = "bookwyrm"
  t.description = "Connect to any BookWyrm instance"
  t.registration_strategy = "bookwyrm"
  t.registration_path = nil
  t.authorization_path = "/o/authorize/"
  t.token_path = "/o/token/"
  t.default_scopes = ["read"]
  t.requires_pkce = true
end

OauthSiteType.find_or_create_by!(slug: "misskey") do |t|
  t.name = "Misskey"
  t.slug = "misskey"
  t.description = "Connect to any Misskey / Sharkey instance"
  t.registration_strategy = "indie_auth"
  t.registration_path = nil
  t.authorization_path = "/oauth/authorize"
  t.token_path = "/oauth/token"
  t.default_scopes = ["read:favorites"]
  t.requires_pkce = true
end

OauthSiteType.find_or_create_by!(slug: "gotosocial") do |t|
  t.name = "GoToSocial"
  t.slug = "gotosocial"
  t.description = "Connect to any GoToSocial instance"
  t.registration_strategy = "mastodon_v1_apps"
  t.registration_path = "/api/v1/apps"
  t.authorization_path = "/oauth/authorize"
  t.token_path = "/oauth/token"
  t.default_scopes = ["read"]
end

OauthSiteType.find_or_create_by!(slug: "mastodon") do |t|
  t.name = "Mastodon"
  t.slug = "mastodon"
  t.description = "Connect to any Mastodon instance"
  t.registration_strategy = "mastodon_v1_apps"
  t.registration_path = "/api/v1/apps"
  t.authorization_path = "/oauth/authorize"
  t.token_path = "/oauth/token"
  t.default_scopes = ["read"]
end

# IndieAuth Settings
if Setting.where(lookup_key: "indieauth_client_id_urls").count == 0
  warn("creating indieauth_client_id_url setting")
  Setting.create!(
    lookup_key: "indieauth_client_id_urls",
    summary: "Public URLs used for Indieauth Client identification",
    description: "<p><code>base_url</code> is a publicly reachable URL that IndieAuth servers
like Misskey and Sharkey will fetch to discover this app's allowed OAuth redirect URIs.
The page at this URL must include a <code>&lt;link rel=\"redirect_uri\"&gt;</code> tag pointing to the
<code>redirect_uri</code> which is the relay page that bounces the browser
back to your local instance. This will default to <code>{base_url}/indeauth-callback</code></p>

<p>Change this only if you are self-hosting the relay page at a different domain.</p>",
    visible: true,
    value_type: "hash",
    value: {value: {base_url: "https://backupbrain.app",
                    redirect_url: "https://backupbrain.app/indieauth-callback"}}
  )
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
        value_type: "string",
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
      value_type: "string",
      value: {value: false}
    }
  )
  warn("creating enable_audio_transcriptions setting path dependency")
  sd = SettingDependency.new(
    dependency_lookup_key: whisper_model_path_lookup_key,
    name: "Whisper Model Path",
    notes: "must be a valid path to a whisper model",
    test: "BackupBrain::WhisperClient.instance.viable?"
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
    value_type: "string",
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
    value_type: "string",
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
      value_type: "boolean",
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
      value_type: "string",
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
      value_type: "boolean",
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

# missing_audio_audio_url setting ─────────────────────────────
if Setting.where(lookup_key: "missing_audio_audio_url").count == 0
  warn("creating missing_audio_audio_url setting")

  Setting.create!(
    {
      lookup_key: "missing_audio_audio_url",
      summary: "url to use when audio file is missing",
      description: "An audio file url that is valid when referenced from within
a rendered page. Can be /path/under/public/dir/missing_audio.mp3
or https://example.com/missing_audio.mp3",
      visible: true,
      value_type: "string",
      value: {value: "/audio/missing_audio_audio.mp3"}
    }
  )
end

# missing_image_image_url setting ─────────────────────────────
if Setting.where(lookup_key: "missing_image_image_url").count == 0
  warn("creating missing_image_image_url setting")

  Setting.create!(
    {
      lookup_key: "missing_image_image_url",
      summary: "url to use when image file is missing",
      description: "An image url that is valid when referenced from within
a rendered page. Can be /path/under/public/dir/missing_image.svg
or https://example.com/missing_image.svg",
      visible: true,
      value_type: "string",
      value: {value: "/images/icons/missing_image_image.svg"}
    }
  )
end

# archival_requests_timeout setting ─────────────────────────────
if Setting.where(lookup_key: "archival_requests_timeout").count == 0
  warn("creating archival_requests_timeout setting")

  Setting.create!(
    {
      lookup_key: "archival_requests_timeout",
      summary: "HTTP timeout in seconds",
      description: "The number of seconds an HTTP request should
wait before giving up on a response when
attempting to archive a bookmarked page.",
      visible: true,
      value_type: "integer",
      value: {value: 10}
    }
  )
end

# gemini_api_key setting ─────────────────────────────
if Setting.where(lookup_key: "gemini_api_key").count == 0
  warn("creating gemini_api_key setting")

  Setting.create!(
    {
      lookup_key: "gemini_api_key",
      summary: "API key for Google Gemini",
      description: "Your Google Gemini API key. Required for AI-powered features such as
audio archive hero image generation.

Obtain a key from Google AI Studio (aistudio.google.com).",
      visible: true,
      value_type: "string",
      value: {value: ""}
    }
  )
end

# gemini_image_prompt_guidance setting ─────────────────────────────
if Setting.where(lookup_key: "gemini_image_prompt_guidance").count == 0
  warn("creating gemini_image_prompt_guidance setting")

  Setting.create!(
    {
      lookup_key: "gemini_image_prompt_guidance",
      summary: "Prompt guidance sent to Gemini when generating hero image prompts for archives",
      description: "Instructions sent to Gemini along with an archive's text and transcript
in order to generate a prompt suitable for Gemini image generation.",
      visible: true,
      value_type: "string",
      value: {value: <<~PROMPT.strip}
        You are helping generate prompts for an AI image generator.  The prompt you generate
        must be two paragraphs at most and it must begin with stylization instructions.
        You do not need to use complete sentences.

        Given the following text from a web page archive or audio transcript,
        identify the key subjects, themes, people, objects, and setting described.
        Then write a concise image generation prompt suitable for
        producing a anime or illustration-style hero image that visually
        represents the content. Focus on the most important concrete visual elements
        and tonal words. Use descriptive but simple language. Do not include
        meta-commentary or explanation — output only the image prompt itself.
      PROMPT
    }
  )
end

# generate_audio_hero_images setting ─────────────────────────────
if Setting.where(lookup_key: "generate_audio_hero_images").count == 0
  warn("creating generate_audio_hero_images setting")

  generate_hero_setting = Setting.create!(
    {
      lookup_key: "generate_audio_hero_images",
      summary: "Generate hero images for audio archives using Gemini",
      description: "When enabled, a background job will use Gemini to generate a square
hero image for each newly archived page that contains audio. The image
is stored locally and displayed alongside the archive and in OS media controls.

Requires a valid gemini_api_key setting.",
      visible: true,
      value_type: "boolean",
      value: {value: false}
    }
  )
  sd = SettingDependency.new(
    dependency_lookup_key: "gemini_api_key",
    name: "Gemini API Key",
    notes: "must be a non-empty Gemini API key",
    test: "Setting.get_value_of_key('gemini_api_key').present? rescue false"
  )
  generate_hero_setting.setting_dependencies << sd
  generate_hero_setting.save!
end

# archival_requests_timeout setting ─────────────────────────────
if Setting.where(lookup_key: "theme_names").count == 0
  warn("creating theme_names setting")

  Setting.create!(
    {
      lookup_key: "theme_names",
      summary: "A list of available themes to choose from",
      description: "These correspond to CSS file names of different themes available to choose from.",
      visible: true,
      value_type: "array",
      value: {value: %w[default ember]}
    }
  )
end
