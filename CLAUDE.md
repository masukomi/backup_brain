# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

BackupBrain (“BB”) is a self-hosted, **single-user** personal knowledge base (Rails 7.1 + MongoDB). It began as a bookmark manager that makes local text-only archives of bookmarked pages. It has since grown into a central store for the user's life: bookmarks, notes, reviews, people and their social media accounts, transcripts of archived audio and video, and a daily timeline across all of them. More record types are expected. Design new features as part of one knowledge base, not as add-ons to bookmarks.

**Single user is a hard invariant.** The `User` model's `before_create` callback blocks a second account. Privacy logic all through the app (`include_private_records?`, `DashboardsController`, API keys acting as `User.first`) assumes that anyone signed in is the owner. Don't introduce multi-user patterns. They would expose private data.

## General

- Never replace ASCII quotes (`"`) with Unicode smart quotes (`“` U+201C / `”` U+201D). Preserve non-ASCII characters exactly as found.
- All user-facing strings go in `config/locales/en.yml`. Never hardcode display text. Mongoid validation-error translations live under the top-level `mongoid:` key, not `activemodel:`.
- Use **HTTParty** for HTTP requests, never `Net::HTTP` directly. For outbound fetches of web pages, send Firefox-like headers (`BackupBrain::RequestHeaders`). Some sites return 403 without them.
- When the user says “BB” they mean this app.

## Commands

```bash
rails s -p 3334                       # dev server
rake jobs:work                        # Delayed Job worker

bundle exec rspec                     # all tests
bundle exec rspec spec/models/bookmark_spec.rb:42

# Lint — agents should never run these
bundle exec standardrb
bundle exec rubocop

rake db:mongoid:create_indexes        # after adding an index to a model
scripts/run_data_migrations.sh        # run pending schema_N data migrations

# Maintenance (lib/tasks/cleanup.rake)
rake cleanup:retry_unarchived
rake cleanup:rearchive_all
rake cleanup:reindex_all              # bookmarks → Meilisearch
rake cleanup:reindex_notes            # resets notes index filterable/sortable attrs, then reindexes
rake cleanup:generate_missing_transcripts
rake cleanup:regenerate_transcripts
rake cleanup:gather_yt_transcripts
rake cleanup:destroy_useless_bookmarks
rake importer:pinboard_import[path,start_at]
```

## Configuration: env vars vs. `Setting`

There are two layers of configuration.

**`.env`** (copy `.env.sample`, loaded by `dotenv-rails`) holds infrastructure: `MONGODB_URL`, `MEILISEARCH_URL`, `MEILI_MASTER_KEY` / `MEILISEARCH_SEARCH_KEY` / `MEILISEARCH_ADMIN_KEY`, `SEARCH_ENABLED`, `HOST_NAME` / `PORT` / `HOST_USES_SSH` (used to build OAuth callback URLs), `DELAYED_JOB_WORKERS`, `LOG_LEVEL`.

**`Setting`** documents in MongoDB hold feature flags and app behaviour. Users edit them at `/settings`. New feature toggles belong here, not in ENV. Examples: `enable_archiving`, `reader_path`, `enable_audio_transcriptions`, `whisper_model_path`, `enable_youtube_transcriptions`, `generate_audio_hero_images`, `gemini_api_key`, `enable_local_ollama` / `ollama_url` / `ollama_model`, `archival_requests_timeout`, `missing_image_image_url`, `schema_version`.

- `Setting.get_value_of_key(key)` raises `BackupBrain::Errors::UnknownSetting` for unknown keys. Pass `safe: true` to get `nil`, or rescue the error (most `enabled?` helpers do).
- Values are stored as `{"value" => ...}` with a `value_type`. Settings are cached and the cache is busted on save.
- `group` is used to group settings in the UI. `visible: false` hides a setting from the default list.
- `embeds_many :setting_dependencies`. A `SettingDependency` names another setting and holds a Ruby `test` string that is `eval`'d. A setting can't be enabled until its dependencies pass. Dependencies are only created via seeds or migrations, never from the UI. `Setting#ignore_dependencies!` / `#honor_dependencies!` bypass the check (used in seeds).
- New settings are created idempotently in `db/seeds.rb` (`if Setting.where(lookup_key: ...).count == 0`). Follow that pattern.

## Architecture

### Database: MongoDB via Mongoid, not ActiveRecord

Every model uses `include Mongoid::Document`. There are no SQL migrations; schema changes are made by adding or removing fields in the model files. When existing data must be transformed, write a **data migration**:

- `scripts/data_migrations/schema_N_migration.rb` is a `rails runner` script. It checks `Setting "schema_version" == N-1`, transforms the data, then bumps `schema_version`.
- Migrations must keep running on old databases long after they're written. Hardcode literal values (tag names, field names) in them instead of referencing app constants, which may be renamed or removed later. `schema_7` broke this way when `FetchMastodonBookmarksJob::MASTODON_TAG` was removed.
- `scripts/run_data_migrations.sh` (via `scripts/bash_helpers/migrations.sh`) runs the next migration file if one is present.
- Mongoid indexes are declarative. Run `rake db:mongoid:create_indexes` after adding one.

### The knowledge base: record types

| Model | What it is | `private` default | Search index | Tags |
|---|---|---|---|---|
| `Bookmark` | A URL plus embedded archives of its content | `false` | `backup_brain_general` | yes |
| `Note` | Standalone Markdown text (`title`, `string_data`, `mime_type`) | **`true`** | `backup_brain_notes` | yes |
| `Review` | Markdown review with `rating`, `source_url`, `image_path`. Imported from BookWyrm or written by hand | **`true`** | `backup_brain_reviews` | yes |
| `Person` | Someone the user tracks: `name`, `aliases`, `pronouns`, `email`, `home_url`, `domains`, avatar | n/a (never public) | `backup_brain_people` | no |
| `SocialMediaAccount` | A profile belonging to a `Person` (or unattached) | n/a | (not wired) | no |

**`Person` / `SocialMediaAccount` are *other people*:** authors and contacts the user tracks, never the user's own accounts. Never use `OauthSite` credentials to impersonate or act as them. The OAuth credentials may only be used as a *proxy* to read public profile data (e.g. GoToSocial lookups through an authenticated Mastodon instance).

Relationships that tie the knowledge base together:

- `Person has_many :social_media_accounts` and `has_and_belongs_to_many :bookmarks`. On create, a Person links every Bookmark whose `domain` is in `person.domains`. On create, a Bookmark links every Person whose `domains` include its domain.
- `Bookmark has_and_belongs_to_many :social_media_accounts`: the account that posted the bookmarked thing. `check_social_media_accounts` (before_save) links one whose `profile_url` matches the bookmark URL.
- **Never put `dependent: :destroy` on the HABTM links between people, accounts and bookmarks.** Deleting a person must not delete bookmarks.
- `Person` fetches a Gravatar avatar if it has an email and no avatar. Missing avatars are set to `MISSING_AVATAR_PATH` so the fetch isn't retried.
- `SocialMediaAccount` detects its service via NodeInfo (`query_service_type`) and normalizes it through `CONSOLIDATED_SERVICE_MAP` (Pleroma/Akkoma/… → mastodon, Firefish/Sharkey/… → misskey, etc.). `SUPPORTED_SERVICES` (mastodon, gotosocial, misskey, bookwyrm families) get `ArchiveSocialMediaAccountJob` after create, which downloads the avatar, header and description. Only one account per person can be `preferred`.

### Conventions shared across record types

When you add a new record type, it should follow these:

- **`private` / `sensitive` flags.** `private` hides a record from anonymous visitors. `sensitive` blurs content in the UI (CSS class `blurred`), so a sensitive Review needs a `title` to show unblurred. Anything personal (notes, reviews, people) defaults to private.
- **Hide-private toggle.** `PrivacyController` sets a `hide_private` cookie. When it's set, even the signed-in owner sees only public records (screen-sharing mode). Respect it via `ApplicationController#include_private_records?`, not by checking `user_signed_in?` directly.
- **Tags.** Tags are lowercase strings with underscores (no spaces), stored as an `Array` on each document *and* mirrored as top-level `Tag` documents (a denormalized design). Include `BackupBrain::Taggable` (`ClassMethods` + `InstanceMethods`) and wire up `clean_tags!` / `clean_orphaned_tags` (before_save), `clean_orphaned_tags` (before_destroy), and `update_central_tags_list` (after_save). `Tag.split_tags` normalizes input. The module provides `tagged_with_all`, `tagged_with_any`, `replace_tag!` and `remove_tag!`. Each taggable type has a `/<type>/tagged_with/:tags` route.
- **Triggers** apply tags and flags automatically:
  - `DomainTrigger`: per-domain rules applied to Bookmarks (`apply_domain_trigger`).
  - `ContentTrigger`: word-match rules applied to the text of `Bookmark`, `Archive`, `Note` and `Review` (`ContentTrigger::SUPPORTED_OBJECT_TYPES`). Add new text-bearing types to that list and call `ContentTrigger.apply_triggers` from a `before_save`.
  - Both use `BackupBrain::Triggers` (`mark_as_private`, `mark_as_sensitive`, `mark_to_read`, `tags`) and cache their records class-wide, busting the cache on save.
- **Emoji.** `BackupBrain::EmojiHelper` + `EMOJIFIABLE_FIELDS` turn `:emoji_name:` into emoji.
- **Search.** `extend Search::ClassMethods`, `include Search::InstanceMethods`, define `SEARCH_INDEX_NAME`, `SEARCHABLE_ATTRIBUTES` and `CLASS_PREFIXED_SEARCH_IDS`, and register the callbacks only `if Search::Client.instance.enabled?`. See Search below.
- **Daily timeline.** `DashboardsController#dailies` (`/dashboards/dailies`) merges Bookmarks, Notes, Reviews and People grouped by day (`BackupBrain::Grouping`). New record types should usually appear there.
- **Files on disk** live under `archives/<object_type>/<id>/` (see `BackupBrain::ArchiveTools#archive_folder_path_for_doc`). `ArchivesController` serves `bookmarks`, `people` and `social_media_accounts`. Add a branch in `set_object` for any new type that stores files.

### Bookmarks, archives and media

- `Bookmark` embeds many `Archive`s and `FailedArchiveAttempt`s, plus one optional `ApiArchiveSource` (`remote_id`, `service`, `oauth_site`) recording that the archive came from a remote API, not from scraping.
- `Archive` stores `string_data` (Markdown), `mime_type`, `manually_edited`, `hero_image_path` and `metadata` (not shown to users). It embeds many `MediaObject`s.
- `MediaObject` (`simple_type` audio|video, `url`, `mime_type`, `hero_image_path`, `alt_text`, `sensitive`) embeds one `Transcription`. Its `after_create :transcribe` enqueues `YouTubeTranscriptionJob` for YouTube videos or `TranscribeAudioJob` (whisper.cpp via `BackupBrain::WhisperClient`) for audio, if each is enabled in Settings.
- `Transcription` (`text`, `status`, `source` youtube|whisper, `source_hash` dedup key) is nested Bookmark → Archive → MediaObject → Transcription. Use `Transcription.get_all` / `get_count` (aggregations) to find them; there is no top-level collection. `text_without_timestamps` strips the timestamps.
- `GenerateHeroImageJob` writes an AI-generated hero image for an archive from its transcript. It builds the image prompt with local Ollama (`enable_local_ollama`) or Gemini and generates the image with Gemini. It's gated on the `generate_audio_hero_images` setting. `BackupBrain::HeroImageFinder` pulls og:image-style hero images out of HTML.
- Useful scopes: `to_read`, `not_to_read`, `public_bookmarks`, `private_bookmarks`, `archived`, `unarchived`, `containing_audio`.
- `suppress_auto_archive!`: call before saving a bookmark whose archive you build yourself. It stops `after_create` / `before_save` from enqueuing `ArchiveUrlJob`. `SocialMediaAccount#suppress_auto_archive_job!` is the equivalent for accounts.

### Archiving pipeline

Requires the `enable_archiving` setting, which depends on `reader_path`.

1. `Bookmark#generate_archive` runs after create, or when the URL changes.
2. It enqueues `ArchiveUrlJob` (async, `:low_priority`), or uses `ArchiveUrlWithoutRetriesJob` (sync).
3. `BackupBrain::ToolDispatcher` picks a tool by domain from `config/archive_tools.yml`. If the tool has `handles_download: true` it gets `{URL}`. Otherwise the job pre-downloads the page with HTTParty and passes `{TEMPFILE}`. Tools write Markdown to stdout. A non-zero exit raises `BackupBrain::Errors::UnarchivableUrl`.
4. Relative URLs are fully qualified. Images, audio and video are downloaded and cached locally under `archives/bookmarks/<id>/` (SHA256-named files), or offloaded to S3 when `enable_s3_storage` is on (see Remote storage below). `MediaObject`s are created, which triggers transcription.
5. Failures are recorded as embedded `FailedArchiveAttempt`s.

Tool entry fields: `name`, `domains` (subdomains match automatically), `command` (`{TEMPFILE}` / `{URL}` placeholders), `handles_download`, `default`. Current tools: `reader` (default), `soundgasm`, `audiochan`, `reddit_posts`, `patreon` (internal JSON API with the Android app UA; exits 1 on paywalled posts). The tool scripts live in `bin/` and share `bin/archive_tool_helper.rb`. Per-domain request headers come from `config/archive_request_headers.yml` via `BackupBrain::RequestHeaders`.

Archiving modules:
- **`BackupBrain::ArchiveTools`**: folder and web-path helpers for any document (`archive_folder_path_for_doc`, `archive_web_path_for_doc`), plus `url_downloadable?` and `url_potentially_good?`.
- **`BackupBrain::Archiver`**: `html_to_archive`, `fully_qualify_urls`, `download_image` / `download_audio` / `download_audio_stream` (ffmpeg for HLS/DASH; falls back to the remote URL) / `download_asset` (detects the extension after download when `extension: nil`), `detect_file_extension`, `record_failed_attempt`.
- `Archive.extract_image_links_from_line`, `extract_audio_urls_from_line` (three-pass: `src=` with an audio extension, `<source type="audio/...">`, and incomplete `<source` fragments with `extension: nil`) and `extract_video_urls_from_line` return `[modified_line, {sha256 => {url:, extension:}}]`. `Archive.extension_for_mime_type` maps MIME types to extensions.
- `BackupBrain::Executables#executable_path` finds binaries. Ones in local `bin/` win over `$PATH`.

### Remote storage of archived files (S3)

Optional. Gated on the `enable_s3_storage` setting (group `remote_storage`), which depends on `s3_bucket`, `s3_access_key_id` and `s3_secret_access_key`. Also `s3_endpoint` (blank = AWS), `s3_region`, `s3_key_prefix`, `s3_force_path_style`, `s3_presigned_url_expiry`. Uses the `aws-sdk-s3` gem against any S3-compatible service.

- **`BackupBrain::S3Storage`** (singleton, `instance`) wraps the client. Keys mirror the disk layout: `archives/bookmarks/<id>/<file>` → `<prefix>bookmarks/<id>/<file>`. It converts between local paths, web paths (`/archives/...`) and `s3://<bucket>/<key>` urls (`key_for`, `web_path_for_s3_url`, `s3_url_for_web_path`), and does `upload`, `head`/`exists?`, `download`, `delete` and `presigned_url`.
- **The bucket must be private.** Nothing links to the bucket directly. `ArchivesController#show` serves the local file if present, otherwise redirects to a short-lived presigned URL when S3 is enabled and holds the object. Markdown, `hero_image_path`, avatar paths etc. keep their `/archives/...` paths and need no rewriting.
- **New archives.** `ArchiveTools#offload_to_remote_storage(path)` uploads a freshly written file and deletes the local copy; `remote_storage_has?` / `remote_storage_web_path_with_prefix` make `download_asset` and `download_audio_stream` skip re-downloads. `ImageGenerationHelpers#store_image` offloads hero images. Call `offload_to_remote_storage` from any new code that writes under `archives/`.
- **`MediaObject#url`** holds `s3://bucket/key` for media in S3 (`Archive#add_media_object` does this for offloaded files). Use `MediaObject#web_path` (not `url`) when building links or feed enclosures; it maps s3 urls back to the `/archives/...` path. `TranscribeAudioJob` downloads S3 audio to a temp file before running whisper.
- **Migrating existing files:** `bundle exec rails runner scripts/upload_archives_to_s3.rb` (flags: `--dry-run`, `--yes`, `--no-backup`, `--delete-local`, `--keep-local`). It offers an `export.sh` backup, uploads `archives/**`, verifies each object (HEAD + size + 1-byte GET through a presigned URL), repoints verified `MediaObject` urls with `set` (no callbacks), then offers to delete the verified local files. Safe to re-run.
- **Deleting records deletes their S3 objects.** `MediaObject` `after_destroy :remove_remote_file` deletes its object unless another MediaObject on the same bookmark still uses the file (`ArchivesController#modify` dups them). `Bookmark#remove_archived_images` (after_destroy) removes the whole `bookmarks/<id>/` prefix via `S3Storage#delete_prefix`, alongside the local `rm_rf`. Both log and swallow S3 errors so a storage hiccup can't block a delete.
- **Zero-byte archive files are always a failed download and are never kept.** `download_asset` deletes the partial file when the download raises, and deletes an empty result and raises `BackupBrain::Errors::EmptyDownload` (a subclass of `UnarchivableUrl`). Image callers then insert `missing_image_image_url`, audio callers `missing_audio_audio_url`, rather than the original remote URL used for other failures. The upload script refuses to upload zero-byte files, rewrites the referencing archive markdown to the placeholder, removes matching `MediaObject`s, and deletes the file.

### Importing from the outside world

Inbound sources, all running on Delayed Job:

- **Fediverse bookmarks.** `FetchMastodonBookmarksJob` (Mastodon API, also GoToSocial) and `FetchMisskeyBookmarksJob` iterate the connected `OauthSite`s. They create Bookmarks tagged `fediverse_bookmark` (`FetchMastodonBookmarksJob::FEDIVERSE_BOOKMARK_TAG`, from `I18n` `tags.default_tags.fediverse_bookmark`) plus a per-service tag: `<slug>_bookmark` (`tags.default_tags.oauth_site_type_bookmark`) for Mastodon, hardcoded `misskey_bookmark` for Misskey. Bookmarks imported before `fediverse_bookmark` existed carry only the legacy `mastodon_bookmark` tag, so code that finds fediverse imports must match both. They call `suppress_auto_archive!`, build the archive from the post content and downloaded media, append YouTube embeds (`embed_youtube_videos`), and create or link the poster's `SocialMediaAccount`. They handle 429s with backoff, fall back to remote URLs when media returns 403, stop paginating at the first known bookmark, and reschedule themselves (`schedule_unless_pending`).
- **BookWyrm reviews.** `FetchBookwyrmReviewsJob` creates `Review`s, deduplicated on `source_url`, and keeps the remote `created_at`.
- **Files.** `HtmlImporter` (browser bookmark exports) and `PinboardImporter` (`UploadImporter` subclasses, at `/importer`), plus `rake importer:pinboard_import`.
- **Browser extension.** Uses the `webextension` layout (`?layout=webextension`). `?closeable=true` makes the success page signal the extension to close the window.
- **API.** Read/write JSON & Markdown, documented in `api_documentation.md`.

`/jobs` (`JobsController`) lists, runs, aborts and unschedules jobs from the UI.

### OAuth2 / remote sites

`OauthSite` + `RemoteCredentialsController` implement the authorization-code flow with dynamic client registration. `OauthSiteType` defines each provider (registration strategy `"mastodon_v1_apps"` or `"rfc7591"`, paths, default scopes). The callback URL comes from `HOST_NAME` / `PORT` / `HOST_USES_SSH`.

### Search

Meilisearch via the `mongodb_meilisearch` gem, enabled by `SEARCH_ENABLED`. Each searchable model has its own index (see the record types table).

- The gem derives filterable and sortable attributes from `SEARCHABLE_ATTRIBUTES`. That is why `created_at`, `updated_at` and `private` are listed for Bookmark and Note: sorting by date and filtering `private = false` depend on it. `Note::QUERYABLE_ATTRIBUTES` is the subset passed as `attributes_to_search_on`.
- Only a bookmark's latest archive is indexed (`archives_text`), because Meilisearch allows at most 65,535 positions per attribute.
- **Changing `SEARCHABLE_ATTRIBUTES` requires a reindex.** `configure_attributes_and_index_if_needed!` won't reconfigure an existing index. Run `rake cleanup:reindex_all` or `rake cleanup:reindex_notes`, or add an equivalent task for a new model.
- `ApplicationController#central_search(search_for:)` serves bookmarks and notes. It sets `@bookmarks`/`@notes`, `@tags_list` and `@pagy` (html only), and renders `:index` (html) or `:search` (json/md). The search form's Bookmarks/Notes pulldown is driven by `search_form_controller.js`. `BookmarksController#search` redirects on `search_for=notes` for no-JS clients. To make a new type searchable, extend `central_search` and the pulldown.

### API, formats and credentials

`/bookmarks/search`, `/notes/search` and the bookmark/note CRUD actions answer html, `.json` and `.md`. Full reference: **`api_documentation.md`**. Update it when you change API behaviour.

| Format | Auth | Pagination |
|---|---|---|
| html | Devise session (optional; anonymous visitors get public records) | paginated |
| `.json` / `.md` | API key required for search | none; all matches up to `ApplicationController::RAW_RESULT_CAP` (10,000) |

- Two **different** credential models, both managed at `/access`:
  - `ApiKey`: expiry plus `read:`/`write:` permissions, sent as `Authorization: Bearer <key>`. No query-param fallback.
  - `SecretKey`: no expiry, used only by `FeedsController` (`/feeds/audio`, `/feeds/to_read` RSS) as `?secret_key=`. Don't copy that pattern elsewhere.
- `app/controllers/concerns/api_key_authenticatable.rb` provides `raw_format?`, `require_api_key!(for_model:)`, `render_api_error` and the narrow CSRF exemption for keyed raw-format requests. Errors answer in the requested format: 401 (missing/unknown/expired key), 403 (missing permission), 400 (blank query), 502 (Meilisearch down). Authenticate the key *before* loading the record, or private records 404.
- Permission strings (`"read:notes"`) come from `BackupBrain::ModelPaths.path_string`, the single source shared with `AccessHelper`. Always use it.
- A valid key acts as the owner (`acting_user` → `User.first`) and sees private records it has read permission for.
- Raw formats run **one** Meilisearch query.
- Use dedicated views (`search.json.jbuilder`, `search.md.erb`, `show.md.erb`). Don't reuse `bookmarks/_bookmark.json.jbuilder` for API output, because it overwrites `url` with the app's own URL.
- **Adding a non-html format?** `config/initializers/overrides.rb` wraps dev-mode templates in `<!-- START PARTIAL -->` comments, guarded by `template.format == :html`. Keep that guard, or json/md/rss output gets corrupted.

### Frontend

- Importmap (no bundler), Hotwire (Turbo + Stimulus; controllers in `app/javascript/controllers/`).
- Two layouts: `application` and `webextension`.
- Themes and light/dark mode: `/administration/themes`, `color_scheme_controller.js`.
- Favicons for domains are fetched and cached by `BackupBrain::Favicons` (`/favicon/:domain_name`).
- `ScriptKiddiesController` catch-all routes answer vulnerability-scanner probes (`.env`, `.php`, `.git/config`). Keep them at the end of `routes.rb`.

### Other lib modules

`BackupBrain::Domains` (domain cleaning/validation, used by Person, Review, DomainTrigger), `HtmlEntityEncoding`, `YouTube` (`video_id`, `embed_url`, `embed_html`), `ImageGenerationHelpers`, `Errors` (`UnarchivableUrl`, `StorageError`, `InvalidTag`, `UnknownSetting`, `UnsupportedDocumentType`, …).

### Service installation

`scripts/services/{macos,systemd}/setup.sh` install launchd plists or systemd units. They `sed`-substitute `/path/to/backup_brain`, `RAILS_ENV` and (systemd) `YOUR_USERNAME` / `USER_GROUP` / the Meilisearch key. The Tailscale Funnel service is opt-in. Keep placeholder paths as `/path/to/backup_brain/...` so one substitution covers them all. Docker compose files and `scripts/{export,import}.sh` cover containerized installs and backups.

## Test patterns

- **No ActiveRecord.** `config.use_active_record = false`. Don't use transactional fixtures or AR-specific helpers.
- **Meilisearch callbacks** (`add_to_search`, `update_in_search`, `remove_from_search`) fire on save/destroy when credentials are configured. Stub all three on instances of any searchable model (Bookmark, Note, Review, Person) before saving.
- **Search in request specs:** stub the class method:

  ```ruby
  allow(Note).to receive(:search).and_return(
    {"matches" => ids.map(&:to_s),
     "search_result_metadata" => {"nbHits" => ids.size}}
  )
  ```

- **Tag cleanup.** Saving tagged records creates `Tag` documents, and `destroy_all` doesn't cascade to them. Call `Tag.destroy_all` in `before`/`after`, or tag uniqueness fails in later specs.
- **Users.** `Bookmark belongs_to :user`, so use `User.first || create(:user)`. Never create a second user.
- **Network.** Person (Gravatar), SocialMediaAccount (NodeInfo, profile lookups, auto-archive job) and the fetch jobs make HTTP calls in callbacks. Stub HTTParty or use the `suppress_*` helpers.
- **Host authorization.** `config/application.rb` adds `'backupbrain'` to `config.hosts`, which enables host checks everywhere. `config/environments/test.rb` calls `config.hosts.clear` so request specs (`www.example.com`) don't get a 403. Keep it.
- FactoryBot and Devise helpers are in `spec/support/`.

### Rubocop in specs

`lefthook`'s pre-commit hook runs rubocop and **blocks commits** on offenses. Two cops come up constantly:

- **`RSpec/MultipleExpectations`** (Max: 1). Split into a `context` with a shared `before` and one `it` per assertion. When the assertions genuinely describe one thing, disable the cop inline on the `it` line:

  ```ruby
  it "asks Meilisearch for everything at once" do # rubocop:disable RSpec/MultipleExpectations
  ```

- **`RSpec/AnyInstance`** can't be avoided when stubbing search callbacks. Wrap the block:

  ```ruby
  # rubocop:disable RSpec/AnyInstance
  before do
    allow_any_instance_of(described_class).to receive(:add_to_search)
    allow_any_instance_of(described_class).to receive(:update_in_search)
    allow_any_instance_of(described_class).to receive(:remove_from_search)
  end
  # rubocop:enable RSpec/AnyInstance
  ```

Use the narrowest disable that works, and never disable a cop in `.rubocop.yml` for one spec. Examples: `spec/models/bookmark_spec.rb`, `spec/requests/search_api_spec.rb`, `spec/requests/records_api_spec.rb`, `spec/controllers/remote_credentials_controller_spec.rb`.
