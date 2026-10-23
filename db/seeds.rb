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
    group: "authentication",
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
        group: "transcription",
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
      group: "transcription",
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
    group: "authentication",
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
    group: "authentication",
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
      group: "transcription",
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
      group: "archiving",
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
      group: "archiving",
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
      group: "archiving",
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
      group: "archiving",
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
      group: "archiving",
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
      group: "generative_ai",
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
# gemini_text_model setting ─────────────────────────────
if Setting.where(lookup_key: "gemini_text_model").count == 0
  warn("creating gemini_text_model setting")

  Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "gemini_text_model",
      summary: "Google Gemini to use for text generation",
      description: "The model Google Gemini should be instructed to use to generate text.",
      visible: true,
      value_type: "string",
      value: {value: "gemini-2.5-flash"}
    }
  )
end
# gemini_image_model setting ─────────────────────────────
if Setting.where(lookup_key: "gemini_image_model").count == 0
  warn("creating gemini_image_model setting")

  Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "gemini_image_model",
      summary: "Google Gemini to use for image generation",
      description: "The model Google Gemini should be instructed to use to generate images.",
      visible: true,
      value_type: "string",
      value: {value: "gemini-2.5-flash-image"}
    }
  )
end

# ollama_url setting ─────────────────────────────
if Setting.where(lookup_key: "ollama_url").count == 0
  warn("creating ollama_url setting")

  Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "ollama_url",
      summary: "Local Ollama Url",
      description: "What url to connect to to talk to Ollama",
      visible: true,
      value_type: "string",
      value: {value: "http://localhost:11434"}
    }
  )
end
# ollama_model setting ─────────────────────────────
if Setting.where(lookup_key: "ollama_model").count == 0
  warn("creating ollama_model setting")

  Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "ollama_model",
      summary: "Local Ollama model",
      description: "What model to instruct Ollama to use. Must be pre-loaded locally.",
      visible: true,
      value_type: "string",
      value: {value: "qwen2.5:7b"}
      # qwen2.5:7b is ~4.7GB, runs quickly
      # and does a good job.
    }
  )
end

# enable_local_ollama setting ─────────────────────────────
if Setting.where(lookup_key: "enable_local_ollama").count == 0
  warn("creating enable_local_ollama setting")

  enable_local_ollama_setting = Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "enable_local_ollama",
      summary: "creates use local ollama models to generate prompts",
      description: "A local ollama instance can process text containing adult content without invoking content filters.",
      visible: true,
      value_type: "boolean",
      value: {value: false}
    }
  )
  sd1 = SettingDependency.new(
    dependency_lookup_key: "ollama_model",
    name: "Ollama Model",
    notes: "must be a valid & installed ollama model",
    test: "Setting.get_value_of_key('ollama_model').present? rescue false"
  )
  sd2 = SettingDependency.new(
    dependency_lookup_key: "ollama_url",
    name: "Ollama URL",
    notes: "must be a valid Ollama Url",
    test: "Setting.get_value_of_key('ollama_url').present? rescue false"
  )
  enable_local_ollama_setting.setting_dependencies << sd1
  enable_local_ollama_setting.setting_dependencies << sd2
  enable_local_ollama_setting.save!
end
# gemini_image_prompt_guidance setting ─────────────────────────────
if Setting.where(lookup_key: "audio_transcript_image_prompt_guidance").count == 0
  warn("creating audio_transcript_image_prompt_guidance setting")

  Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "audio_transcript_image_prompt_guidance",
      summary: "Prompt guidance sent to an image generation AI when generating hero image prompts for archives",
      description: "Instructions to be sent along with an archive's text and transcript
in order to generate a prompt suitable for image generation.",
      visible: true,
      value_type: "string",
      value: {value: <<~PROMPT.strip}
        You are helping generate prompts for an AI image generator that must strictly comply with Google's Generative AI Prohibited Use Policy. The prompt you generate must be two paragraphs at most.

        Read the following audio transcript. Determine the number of characters in the scene. Pay special attention to gender markers to determine the gender of the characters. If you are unsure about the gender of a character describe them as being androgynous.  Determine what activities they are describing or participating in, any physical or emotional dynamic between them, and any notable objects or setting details in the scene.

        Before generating the image prompt, apply the following single content rule:
        - If the content depicts or describes nudity or exposed body parts, represent the
            people as clothed in contextually appropriate attire instead, preserving as much
            of the scene's mood, physical closeness, and emotional dynamic as possible.

        Then write a concise image generation prompt suitable for that visually represents the content.

        Focus on the most important concrete visual elements and tonal words. Use descriptive but simple language. Do not include meta-commentary, explanation, or headings. Output only the image prompt itself.

        Start the prompt with instructions to produce a square image with a modern manga style.
      PROMPT
    }
  )
end

# generate_audio_hero_images setting ─────────────────────────────
if Setting.where(lookup_key: "generate_audio_hero_images").count == 0
  warn("creating generate_audio_hero_images setting")

  generate_hero_setting = Setting.create!(
    {
      group: "generative_ai",
      lookup_key: "generate_audio_hero_images",
      summary: "Generate hero images for audio archives using Gemini",
      description: "When enabled, a background job will use Gemini to generate a square
hero image for each newly archived page that contains audio. The image
is stored locally and displayed alongside the archive and in OS media controls.

Requires a valid gemini_api_key setting.
⚠️ Explicit content will be blocked by Google's content filters.
Use local ollama to generate the prompt if you're archiving audio
that contains or discusses sexual topics.",
      visible: true,
      value_type: "boolean",
      value: {value: false}
    }
  )
  # must be present
  sd1 = SettingDependency.new(
    dependency_lookup_key: "gemini_api_key",
    name: "Gemini API Key",
    notes: "must be a non-empty Gemini API key",
    test: "Setting.all_truthy?(%w[gemini_api_key gemini_text_model]) || Setting.get_value_of_key('enable_local_ollama', safe: true) rescue false"
  )
  # must be present unless enable_local_ollama
  sd2 = SettingDependency.new(
    dependency_lookup_key: "gemini_text_model",
    name: "Gemini Text Model",
    notes: "must be a non-empty Gemini text model",
    test: "Setting.any_truthy?(%w[gemini_text_model enable_local_ollama]) rescue false"
  )
  # must be present
  sd3 = SettingDependency.new(
    dependency_lookup_key: "gemini_image_model",
    name: "Gemini Text Model",
    notes: "must be a non-empty Gemini text model",
    test: "Setting.get_value_of_key('gemini_image_model').present? rescue false"
  )
  generate_hero_setting.setting_dependencies << sd1
  generate_hero_setting.setting_dependencies << sd2
  generate_hero_setting.setting_dependencies << sd3
  generate_hero_setting.ignore_dependencies!
  generate_hero_setting.save!
end

# archival_requests_timeout setting ─────────────────────────────
if Setting.where(lookup_key: "theme_names").count == 0
  warn("creating theme_names setting")

  Setting.create!(
    {
      group: "interface",
      lookup_key: "theme_names",
      summary: "A list of available themes to choose from",
      description: "These correspond to CSS file names of different themes available to choose from.",
      visible: true,
      value_type: "array",
      value: {value: %w[default ember]}
    }
  )
end

# S3 compatible remote storage settings ─────────────────────────────
# Archived assets (images, audio, …) can optionally live on any
# S3 compatible service instead of the local archives/ folder.
# The bucket must be PRIVATE: BackupBrain hands out short-lived
# presigned URLs, so assets are only reachable via requests it starts.
s3_string_settings = {
  "s3_endpoint" => [
    "Endpoint URL of your S3 compatible service",
    "The base URL of the S3 API, e.g. https://s3.us-west-004.backblazeb2.com,
https://<account_id>.r2.cloudflarestorage.com or http://localhost:9000 for MinIO.

Leave blank to use AWS S3 (the region setting is used instead).",
    ""
  ],
  "s3_region" => [
    "Region of your S3 bucket",
    "AWS region name such as us-east-1. Many S3 compatible services accept
any value here (Cloudflare R2 uses \"auto\"). Defaults to us-east-1 when blank.",
    "us-east-1"
  ],
  "s3_bucket" => [
    "Name of the PRIVATE bucket archived assets are stored in",
    "The bucket must NOT allow public reads. BackupBrain generates
presigned URLs for every download, so a public bucket would defeat
the access restriction.",
    ""
  ],
  "s3_access_key_id" => [
    "Access key ID (token id) issued by your S3 compatible service",
    "The identifier half of the credentials your service issued for BackupBrain.
Backblaze calls this the \"keyID\", Cloudflare R2 the \"Access Key ID\",
MinIO the \"Access Key\". Grant it read, write and list access to the bucket above.",
    ""
  ],
  "s3_secret_access_key" => [
    "Secret access key (token secret) issued by your S3 compatible service",
    "The secret half of the credentials. Backblaze calls this the \"applicationKey\",
Cloudflare R2 and MinIO the \"Secret Access Key\". Keep it private.",
    ""
  ],
  "s3_key_prefix" => [
    "Optional folder (key prefix) inside the bucket",
    "Lets several apps share one bucket. For example \"backup_brain\" stores
objects as backup_brain/bookmarks/<id>/<file>. Leave blank to store them
at the root of the bucket. Don't change this after uploading.",
    ""
  ]
}
s3_string_settings.each do |lookup_key, (summary, description, default)|
  next unless Setting.where(lookup_key: lookup_key).count == 0
  warn("creating #{lookup_key} setting")
  Setting.create!(
    {
      group: "remote_storage",
      lookup_key: lookup_key,
      summary: summary,
      description: description,
      visible: true,
      value_type: "string",
      value: {value: default}
    }
  )
end

if Setting.where(lookup_key: "s3_force_path_style").count == 0
  warn("creating s3_force_path_style setting")
  Setting.create!(
    {
      group: "remote_storage",
      lookup_key: "s3_force_path_style",
      summary: "Use path-style S3 URLs (https://endpoint/bucket/key)",
      description: "Most S3 compatible services (MinIO, Garage, Backblaze, R2) want
path-style addressing. Set to false for virtual-host style
(https://bucket.endpoint/key), which AWS S3 prefers.",
      visible: true,
      value_type: "boolean",
      value: {value: true}
    }
  )
end

if Setting.where(lookup_key: "s3_presigned_url_expiry").count == 0
  warn("creating s3_presigned_url_expiry setting")
  Setting.create!(
    {
      group: "remote_storage",
      lookup_key: "s3_presigned_url_expiry",
      summary: "Seconds a presigned download URL stays valid",
      description: "When a browser asks BackupBrain for an archived asset that lives
in S3, BackupBrain redirects it to a presigned URL that expires after
this many seconds. One hour (3600) is plenty for a page load; S3 caps
presigned URLs at 7 days (604800).",
      visible: true,
      value_type: "integer",
      value: {value: 3600}
    }
  )
end

if Setting.where(lookup_key: "enable_s3_storage").count == 0
  warn("creating enable_s3_storage setting")
  s3_setting = Setting.create!(
    {
      group: "remote_storage",
      lookup_key: "enable_s3_storage",
      summary: "Store newly archived assets on your S3 compatible service",
      description: "When enabled, images and audio downloaded while archiving are
uploaded to the configured bucket and removed from the local
archives/ folder. Downloads are served through short-lived presigned
URLs so only requests started by BackupBrain can fetch them.

Fill in s3_bucket, s3_access_key_id and s3_secret_access_key
(and s3_endpoint unless you use AWS) before enabling this.

To move EXISTING archives to the bucket run:
  bundle exec rails runner scripts/upload_archives_to_s3.rb",
      visible: true,
      value_type: "boolean",
      value: {value: false}
    }
  )
  sd = SettingDependency.new(
    dependency_lookup_key: "s3_bucket",
    name: "S3 connection details",
    notes: "s3_bucket, s3_access_key_id and s3_secret_access_key must all be filled in",
    test: "BackupBrain::S3Storage.configured?"
  )
  s3_setting.setting_dependencies << sd
  s3_setting.ignore_dependencies!
  s3_setting.save!
end
