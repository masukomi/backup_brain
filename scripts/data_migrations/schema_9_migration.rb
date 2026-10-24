require "paint"
require "httparty"
require "json"
require "uri"

# Bookmarks imported from Mastodon / GoToSocial / Misskey before June 2026
# have no embedded ApiArchiveSource, so "Re-archive This" falls back to the
# HTML reader instead of re-fetching the post through the connected
# instance's API. Backfill the source by asking each connected instance to
# look the post up by URL.
#
# Mastodon-family: GET /api/v2/search?q=<url>&type=statuses
#   first without `resolve` (only finds posts the instance already knows,
#   i.e. the instance the bookmark was fetched through), then with
#   resolve=true as a fallback.
# Misskey: the note id is in the URL when the note is local to the
#   instance, otherwise POST /api/ap/show {uri: <url>}.
#
# Values are hardcoded on purpose: this must keep working on old databases
# long after the app's constants have moved on.
#
# DRY_RUN=1 resolves everything and prints what it would do, writes nothing,
# and ignores the schema_version gate.

DRY_RUN = ENV["DRY_RUN"].present?
REQUEST_TIMEOUT = 30
MASTODON_FAMILY_SLUGS = %w[mastodon gotosocial].freeze
FEDIVERSE_TAGS = %w[fediverse_bookmark mastodon_bookmark misskey_bookmark].freeze

def migration_get(url, token:, query: {})
  res = HTTParty.get(url,
    query: query,
    headers: {"Authorization" => "Bearer #{token}", "Accept" => "application/json"},
    timeout: REQUEST_TIMEOUT)
  if res.code == 429
    wait = res.headers["retry-after"].to_i
    wait = 60 if wait <= 0
    warn Paint["⏳ rate limited by #{url}, sleeping #{wait}s", :yellow]
    sleep(wait)
    res = HTTParty.get(url,
      query: query,
      headers: {"Authorization" => "Bearer #{token}", "Accept" => "application/json"},
      timeout: REQUEST_TIMEOUT)
  end
  res
end

def migration_post_json(url, body)
  HTTParty.post(url,
    headers: {"Content-Type" => "application/json", "Accept" => "application/json"},
    body: body.to_json,
    timeout: REQUEST_TIMEOUT)
end

# @return [String, nil] the status id as known by `site`
def mastodon_status_id(site, bookmark_url, resolve:)
  query = {q: bookmark_url, type: "statuses", limit: 5}
  query[:resolve] = true if resolve
  res = migration_get("#{site.base_url}/api/v2/search", token: site.access_token, query: query)
  unless res.success?
    warn Paint["   #{site.base_url} search returned #{res.code}", :yellow]
    return nil
  end
  statuses = JSON.parse(res.body)["statuses"] || []
  exact = statuses.find { |s| [s["url"], s["uri"]].include?(bookmark_url) }
  exact ||= statuses.first if statuses.size == 1
  exact&.dig("id")&.to_s
rescue JSON::ParserError, HTTParty::Error, SocketError, Timeout::Error, SystemCallError => e
  warn Paint["   #{site.base_url} search failed: #{e.class}: #{e.message}", :yellow]
  nil
end

# @return [String, nil] the note id as known by `site`
def misskey_note_id(site, bookmark_url)
  local = bookmark_url.match(%r{\A#{Regexp.escape(site.base_url)}/notes/([^/?#]+)}i)
  return local[1] if local

  res = migration_post_json("#{site.base_url}/api/ap/show", {i: site.access_token, uri: bookmark_url})
  unless res.success?
    warn Paint["   #{site.base_url} ap/show returned #{res.code}", :yellow]
    return nil
  end
  parsed = JSON.parse(res.body)
  return nil unless parsed["type"] == "Note"
  parsed.dig("object", "id")&.to_s
rescue JSON::ParserError, HTTParty::Error, SocketError, Timeout::Error, SystemCallError => e
  warn Paint["   #{site.base_url} ap/show failed: #{e.class}: #{e.message}", :yellow]
  nil
end

# Sites whose slug matches the bookmark's `<slug>_bookmark` tag go first.
def order_sites(sites, tags)
  sites.sort_by { |s| tags.include?("#{s.oauth_site_type&.slug}_bookmark") ? 0 : 1 }
end

# @return [Array(String service, String remote_id, OauthSite), nil]
def resolve_source(bookmark, mastodon_sites, misskey_sites)
  tags = bookmark.tags || []
  if tags.include?("misskey_bookmark")
    order_sites(misskey_sites, tags).each do |site|
      id = misskey_note_id(site, bookmark.url)
      return ["misskey", id, site] if id
    end
    return nil
  end

  sites = order_sites(mastodon_sites, tags)
  [false, true].each do |resolve|
    sites.each do |site|
      id = mastodon_status_id(site, bookmark.url, resolve: resolve)
      return ["mastodon", id, site] if id
    end
  end
  nil
end

schema_version_setting = Setting.where(lookup_key: "schema_version").first
if DRY_RUN || schema_version_setting&.inner_value == 8
  puts "Beginning migration to schema_version 9#{" (DRY RUN)" if DRY_RUN}"

  usable = ->(site) { site.access_token.present? }
  mastodon_sites = OauthSite.in(oauth_site_type_id: OauthSiteType.in(slug: MASTODON_FAMILY_SLUGS).pluck(:_id)).select(&usable)
  misskey_sites = OauthSite.in(oauth_site_type_id: OauthSiteType.where(slug: "misskey").pluck(:_id)).select(&usable)

  tags = FEDIVERSE_TAGS + OauthSiteType.pluck(:slug).compact.map { |slug| "#{slug}_bookmark" }
  candidates = Bookmark.any_in(tags: tags.uniq).where(:api_archive_source.exists => false)
  puts "#{candidates.count} fediverse bookmark(s) without an api_archive_source"
  if mastodon_sites.empty? && misskey_sites.empty? && candidates.count > 0
    warn Paint["⚠️  No connected OauthSite with an access token. Nothing can be resolved.", :red]
  end

  done = 0
  unresolved = 0
  failed = 0
  candidates.each do |bookmark|
    service, remote_id, site = resolve_source(bookmark, mastodon_sites, misskey_sites)
    unless remote_id
      unresolved += 1
      warn Paint["❓ Unresolved: #{bookmark.url}", :yellow]
      next
    end

    if DRY_RUN
      puts Paint["   would set #{service}:#{remote_id} via #{site.base_url} on #{bookmark.url}", :cyan]
      done += 1
      next
    end

    bookmark.suppress_auto_archive!
    bookmark.build_api_archive_source(remote_id: remote_id, service: service, oauth_site: site)
    bookmark.save!
    done += 1
    puts Paint["✅ #{service}:#{remote_id} via #{site.base_url} on #{bookmark.url}", :green]
  rescue => e
    failed += 1
    warn Paint["⚠️  Failed to update bookmark #{bookmark._id} (#{bookmark.url}): #{e.message}", :red]
  end

  puts Paint["✅ #{DRY_RUN ? "Would backfill" : "Backfilled"} api_archive_source on #{done} bookmark(s)", :green]
  warn Paint["❓ #{unresolved} bookmark(s) could not be found on any connected instance (left alone; they keep using the HTML reader)", :yellow] if unresolved > 0
  warn Paint["⚠️  Failed to update #{failed} bookmark(s)", :red] if failed > 0

  unless DRY_RUN
    schema_version_setting.set_value_and_type(9)
    if schema_version_setting.save
      puts Paint["✅ Updated schema_version setting to 9", :green]
    else
      warn Paint["⚠️  Unable to update schema_version setting to 9", :red]
      exit 70 # EX_SOFTWARE
    end
  end
end
exit 0
