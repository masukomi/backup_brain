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
# Mastodon-family: walk the account's own bookmark list
#   (GET /api/v1/bookmarks, paginated) once per instance and match on url.
#   Anything not in a list falls back to GET /api/v2/search?q=<url>
#   &type=statuses, first without `resolve` then with resolve=true.
#   Search by url has proven flaky, hence the list first.
# Misskey: the note id is in the URL when the note is local to the
#   instance, otherwise POST /api/ap/show {uri: <url>}.
#
# Values are hardcoded on purpose: this must keep working on old databases
# long after the app's constants have moved on.
#
# DRY_RUN=1 resolves everything and prints what it would do, writes nothing,
# and ignores the schema_version gate.

# keep stdout and stderr interleaved in order when the output is redirected
$stdout.sync = true
$stderr.sync = true

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

# Walks the account's bookmark list on `site` once and maps each
# bookmarked status url (and uri) to its id on that instance. These
# bookmarks were imported from exactly this list, so it is the most
# reliable source; search by url is only a fallback.
# @return [Hash{String => String}]
def mastodon_bookmarked_status_ids(site)
  ids = {}
  url = "#{site.base_url}/api/v1/bookmarks"
  query = {limit: 40}
  pages = 0
  while url && pages < 500
    res = migration_get(url, token: site.access_token, query: query)
    unless res.success?
      warn Paint["   #{site.base_url} bookmark list returned #{res.code} after #{pages} page(s)", :yellow]
      break
    end
    JSON.parse(res.body).each do |status|
      [status["url"], status["uri"]].compact.each { |u| ids[u] ||= status["id"].to_s }
    end
    pages += 1
    query = {} # the next link carries its own params
    url = res.headers["link"].to_s.match(/<([^>]+)>;\s*rel="next"/)&.[](1)
  end
  puts "   #{site.base_url}: #{ids.size} url(s) from #{pages} page(s) of bookmarks"
  ids
rescue JSON::ParserError, HTTParty::Error, SocketError, Timeout::Error, SystemCallError => e
  warn Paint["   #{site.base_url} bookmark list failed: #{e.class}: #{e.message}", :yellow]
  ids
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
  # Only an exact url/uri match counts: a url search also returns posts
  # that merely mention the url, and those are the wrong status entirely.
  exact = statuses.find { |s| [s["url"], s["uri"]].include?(bookmark_url) }
  id = exact&.dig("id")&.to_s
  unless id
    others = statuses.map { |s| s["url"] || s["uri"] }.compact
    detail = others.empty? ? "no statuses returned" : "#{others.size} non-matching status(es): #{others.join(", ")}"
    puts Paint["   #{site.base_url} (resolve=#{resolve}): #{detail}", :yellow]
  end
  id
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
  id = (parsed.dig("object", "id")&.to_s if parsed["type"] == "Note")
  puts Paint["   #{site.base_url} ap/show: no Note returned (type=#{parsed["type"].inspect})", :yellow] unless id
  id
rescue JSON::ParserError, HTTParty::Error, SocketError, Timeout::Error, SystemCallError => e
  warn Paint["   #{site.base_url} ap/show failed: #{e.class}: #{e.message}", :yellow]
  nil
end

# Sites whose slug matches the bookmark's `<slug>_bookmark` tag go first.
def order_sites(sites, tags)
  sites.sort_by { |s| tags.include?("#{s.oauth_site_type&.slug}_bookmark") ? 0 : 1 }
end

# @return [Array(String service, String remote_id, OauthSite), nil]
def resolve_source(bookmark, mastodon_sites, misskey_sites, bookmark_lists)
  tags = bookmark.tags || []
  if tags.include?("misskey_bookmark")
    order_sites(misskey_sites, tags).each do |site|
      id = misskey_note_id(site, bookmark.url)
      return ["misskey", id, site] if id
    end
    return nil
  end

  sites = order_sites(mastodon_sites, tags)
  sites.each do |site|
    id = bookmark_lists[site][bookmark.url]
    return ["mastodon", id, site] if id
  end
  puts Paint["   not in any bookmark list; trying search", :yellow]
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
  if mastodon_sites.empty? && misskey_sites.empty?
    warn Paint["⚠️  No connected OauthSite with an access token. Nothing can be resolved.", :red] if candidates.count > 0
  else
    described = (mastodon_sites + misskey_sites).map { |s| "#{s.base_url} (#{s.oauth_site_type&.slug})" }
    puts "Searching via: #{described.join(", ")}"
  end

  bookmark_lists = {}
  if candidates.count > 0 && mastodon_sites.any?
    puts "Loading bookmark lists…"
    mastodon_sites.each { |site| bookmark_lists[site] = mastodon_bookmarked_status_ids(site) }
  end

  done = 0
  unresolved = 0
  failed = 0
  candidates.each do |bookmark|
    puts "🔎 #{bookmark.url}"
    service, remote_id, site = resolve_source(bookmark, mastodon_sites, misskey_sites, bookmark_lists)
    unless remote_id
      unresolved += 1
      warn Paint["❓ Unresolved: #{bookmark.url}", :yellow]
      next
    end

    if DRY_RUN
      puts Paint["   would set #{service}:#{remote_id} via #{site.base_url}",:cyan]
      done += 1
      next
    end

    bookmark.suppress_auto_archive!
    bookmark.build_api_archive_source(remote_id: remote_id, service: service, oauth_site: site)
    bookmark.save!
    done += 1
    puts Paint["✅ #{service}:#{remote_id} via #{site.base_url}",:green]
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
