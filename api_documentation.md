# BackupBrain API

BackupBrain is a **single-user** instance. An API key belongs to you, the owner —
there is no concept of other users, sharing, or delegated access. Treat a key as
equivalent to your own login for whatever it has been granted.

All examples below assume the instance is at `http://localhost:3334`. Substitute
your own host.

- [Authentication](#authentication)
- [Errors](#errors)
- [Searching bookmarks & notes](#searching-bookmarks--notes)
- [Bookmarks](#bookmarks)
- [Notes](#notes)
- [MCP server](#mcp-server)
- [Quirks & gotchas](#quirks--gotchas)

---

## Authentication

### Creating a key

Keys are created through the web UI at **`/access` → API Keys → New API Key**. When
you create one you choose:

- a **name** (for your own reference)
- an optional **expiration date** — leave blank for a key that never expires
- the **permissions** the key carries

The key is shown **once**, on the page immediately after creation. There is no way
to retrieve it afterwards; if you lose it, delete the key and make a new one.

### Using a key

Send it as a Bearer token:

```
Authorization: Bearer 0123456789abcdef...
```

```bash
curl -H "Authorization: Bearer $BB_KEY" \
     "http://localhost:3334/notes/search.json?query=jabberwocky"
```

There is **no query-parameter fallback** — a key in a URL leaks into server logs,
browser history, and referrer headers.

> The RSS feeds at `/feeds/audio` and `/feeds/to_read` use a `?secret_key=` query
> parameter instead. That is a **different** credential (a *Secret Key*, also managed
> at `/access`) and it does not work on any endpoint documented here.

### Permission scopes

A permission is `<action>:<collection>`. The two collections relevant here are
`bookmarks` and `notes`.

| Scope | Grants |
|---|---|
| `read:bookmarks` | Search bookmarks; read private bookmarks and their archives |
| `write:bookmarks` | Create and update bookmarks |
| `read:notes` | Search notes; read private notes |
| `write:notes` | Create and update notes |

Scopes are checked per endpoint, per collection. A key with only `read:notes`
searching bookmarks gets a `403`, not an empty result set. Write scopes do **not**
imply read scopes — grant both if your client needs both.

### What a key changes

Requesting JSON or Markdown does not merely change the formatting; it changes what
you can see.

| Caller | Sees |
|---|---|
| No key | Public records only. Private records return `404`. |
| Key with `read:<collection>` | Everything in that collection, public and private. |

A `404` on a private record is deliberate — an anonymous caller can't distinguish
"this is private" from "this doesn't exist".

### Which endpoints require a key

| Endpoint | Key required? |
|---|---|
| `GET /{bookmarks,notes}/search.{json,md}` | **Yes** — always |
| `GET /{bookmarks,notes}/:id.{json,md}` | Only to see private records |
| `POST`/`PATCH` `/{bookmarks,notes}.json` | **Yes** (or a logged-in browser session) |

The HTML pages are unchanged and still use your normal browser login.

---

## Errors

Errors come back in the format you asked for — JSON for `.json`, Markdown for `.md`.

```json
{"error": "That API key lacks the 'read:bookmarks' permission."}
```

| Status | Meaning |
|---|---|
| `400 Bad Request` | Search called with no query |
| `401 Unauthorized` | Key missing, unknown, or expired. Response carries `WWW-Authenticate: Bearer` |
| `403 Forbidden` | Key is valid but lacks the required scope |
| `404 Not Found` | No such record, **or** it's private and you didn't present a key that can read it |
| `422 Unprocessable Content` | Validation failed on a create/update. See below. |
| `502 Bad Gateway` | Meilisearch is unreachable or misconfigured |

A `422` carries the failing fields, keyed by attribute name:

```json
{"errors": {"url": ["has already been taken"]}}
```

---

## Searching bookmarks & notes

```
GET /bookmarks/search.json
GET /bookmarks/search.md
GET /notes/search.json
GET /notes/search.md
```

Requires `read:bookmarks` or `read:notes` respectively. Search is powered by
Meilisearch and must be enabled (`SEARCH_ENABLED=true`).

**Raw formats are not paginated.** You get every match in one response, up to a
ceiling of 10,000. `page` and `limit` are ignored — they apply only to the HTML
pages.

### Parameters

| Parameter | Applies to | Notes |
|---|---|---|
| `query` | both | **Required.** Blank → `400`. |
| `tags` | both | Comma-separated. ANDed together, and ANDed with any hashtags in `query`. |
| `sort` | both | `match` (default, by relevance) or `newest` (by `created_at` descending). |
| `search_archives` | bookmarks | `true` to also search the archived page text. Default `false`. Meaningless for notes — notes have no archives. |

Without `search_archives=true`, a bookmark search matches on `title`,
`description`, `tags`, and `url`. A note search always matches on `title`,
`string_data`, and `tags`.

### Hashtag syntax in the query

You can put tags directly in the query string with a `#` prefix. They are pulled
out of the query text before it reaches the search engine and applied as tag
filters:

```
?query=brillig %23poetry
```

is exactly equivalent to

```
?query=brillig&tags=poetry
```

Details:

- A hashtag is a `#` at the start of the query or after whitespace, running to the
  next whitespace: `#poetry`, `#sci-fi`, `#to_read`.
- Tags are **lowercased**. `#Poetry` and `#poetry` are the same tag.
- Multiple hashtags are ANDed: `#poetry #victorian` matches records with both.
- The hashtags are stripped from the text query. `brillig #poetry` searches for
  `brillig`, filtered to the `poetry` tag — it does **not** search for the literal
  string `#poetry`.
- Hashtags and the `tags` parameter combine; they don't override each other.
- A query consisting *only* of hashtags has an empty text query after extraction.
  In JSON/Markdown that's a `400` — use the `tags` parameter for a pure tag lookup.

Remember to URL-encode `#` as `%23`, or your HTTP client will treat it as a
fragment and never send it.

### JSON response

```bash
curl -H "Authorization: Bearer $BB_KEY" \
     "http://localhost:3334/bookmarks/search.json?query=brillig%20%23poetry&sort=newest"
```

```json
{
  "query": "brillig",
  "tags": ["poetry"],
  "total": 2,
  "results": [
    {
      "id": "64a838dd906b1d182175f254",
      "title": "Jabberwocky",
      "description": "Twas brillig, and the slithy toves",
      "tags": ["poetry", "victorian"],
      "created_at": "2023-07-07T12:34:56.000Z",
      "updated_at": "2023-07-07T12:34:56.000Z",
      "url": "https://example.com/jabberwocky",
      "app_url": "http://localhost:3334/bookmarks/64a838dd906b1d182175f254",
      "private": false,
      "to_read": false,
      "sensitive": false,
      "archived": true
    }
  ]
}
```

`query` and `tags` echo back what the server actually searched for **after**
hashtag extraction, which is the easiest way to confirm your tags parsed the way
you expected. `url` is the bookmarked page; `app_url` is the record inside
BackupBrain. `archived` says whether an archive exists — use the archive endpoint
below to fetch it.

Note results use the same envelope, with note fields:

```json
{
  "query": "brillig",
  "tags": [],
  "total": 1,
  "results": [
    {
      "id": "69dd541fb1a9dabdb5ad3e29",
      "title": null,
      "string_data": "’Twas brillig, and the slithy toves…",
      "tags": [],
      "mime_type": "text/markdown",
      "created_at": "2026-01-02T03:04:05.000Z",
      "updated_at": "2026-01-02T03:04:05.000Z",
      "app_url": "http://localhost:3334/notes/69dd541fb1a9dabdb5ad3e29",
      "private": true,
      "sensitive": false
    }
  ]
}
```

### Markdown response

```bash
curl -H "Authorization: Bearer $BB_KEY" \
     "http://localhost:3334/bookmarks/search.md?query=brillig"
```

```markdown
# Search: brillig

2 result(s)

---

## [Jabberwocky](https://example.com/jabberwocky)

#poetry #victorian

Twas brillig, and the slithy toves
```

Bookmarks link to the bookmarked URL; notes link back into BackupBrain. The
Markdown form is a summary — it carries each record's description or body, not the
full archived page. For that, fetch the archive directly.

---

## Bookmarks

### Viewing a bookmark & its latest archive

```
GET /bookmarks/:id.json
GET /bookmarks/:id.md
```

No key needed for a public bookmark. A private one needs `read:bookmarks`,
otherwise `404`.

**`.md` returns the raw Markdown of the most recent archive** — the archived text
of the page itself:

```bash
curl -H "Authorization: Bearer $BB_KEY" \
     "http://localhost:3334/bookmarks/64a838dd906b1d182175f254.md"
```

```markdown
# Jabberwocky

’Twas brillig, and the slithy toves
Did gyre and gimble in the wabe…
```

If the bookmark has no Markdown archive (archiving failed, is disabled, or hasn't
run yet), this returns `404`. Check `archived` in a search result, or `archives` in
the JSON, before assuming there's something to fetch.

To fetch a **specific** archive rather than the latest, pass `archive_id` with an
id from the `archives` array:

```
GET /bookmarks/:id.md?archive_id=<archive_id>
```

`.json` returns the bookmark record with archive **metadata** — archive bodies are
deliberately excluded, since they can be very large:

```json
{
  "_id": "64a838dd906b1d182175f254",
  "url": "https://example.com/jabberwocky",
  "title": "Jabberwocky",
  "description": "Twas brillig…",
  "domain": "example.com",
  "tags": ["poetry"],
  "private": false,
  "sensitive": false,
  "to_read": false,
  "created_at": "2023-07-07T12:34:56.000Z",
  "updated_at": "2023-07-07T12:34:56.000Z",
  "user_id": "…",
  "person_ids": [],
  "social_media_account_ids": [],
  "failed_archive_attempts": [],
  "archives": [
    {
      "_id": "64a838de906b1d182175f255",
      "mime_type": "text/markdown",
      "created_at": "2023-07-07T12:35:02.000Z",
      "updated_at": "2023-07-07T12:35:02.000Z",
      "manually_edited": false,
      "hero_image_path": null,
      "metadata": {},
      "transcription_ids": []
    }
  ]
}
```

Use each entry's `_id` as `archive_id`. Archives are ordered oldest-first, so the
latest is the last element.

### Creating a bookmark

```
POST /bookmarks.json
```

Requires `write:bookmarks`.

```bash
curl -X POST "http://localhost:3334/bookmarks.json" \
     -H "Authorization: Bearer $BB_KEY" \
     -H "Content-Type: application/json" \
     -d '{
           "bookmark": {
             "url": "https://example.com/jabberwocky",
             "title": "Jabberwocky",
             "description": "Lewis Carroll, 1871",
             "tags": ["poetry", "victorian"],
             "private": false,
             "to_read": true
           }
         }'
```

Note the `bookmark` wrapper object — attributes are nested under it.

| Field | Type | Notes |
|---|---|---|
| `url` | string | **Required.** Must be unique — a duplicate is a `422`. |
| `title` | string | **Required.** |
| `description` | string | |
| `tags` | array of strings, or a string | See "Tag formats" below. |
| `private` | boolean | Defaults to `false`. |
| `sensitive` | boolean | Defaults to `false`. Blurs the entry in the UI. |
| `to_read` | boolean | Defaults to `false`. |

Responds `201 Created` with the bookmark, or `422` with `{"errors": {...}}`.

**Archiving happens automatically and asynchronously.** Creating a bookmark
enqueues a background job to fetch and archive the page, so the archive will not be
available in the same response. A `rake jobs:work` worker must be running for it to
happen at all.

### Updating a bookmark

```
PATCH /bookmarks/:id.json
PUT   /bookmarks/:id.json
```

Requires `write:bookmarks`. Send only the fields you want changed:

```bash
curl -X PATCH "http://localhost:3334/bookmarks/64a838dd906b1d182175f254.json" \
     -H "Authorization: Bearer $BB_KEY" \
     -H "Content-Type: application/json" \
     -d '{"bookmark": {"to_read": false, "tags": ["poetry", "read"]}}'
```

Responds `200 OK`, or `422` with `{"errors": {...}}`.

**`tags` replaces the whole list** — it is not additive. To add a tag, send the
full new set. **Changing the `url` triggers re-archiving.**

---

## Notes

Notes are free-form Markdown text records. Unlike bookmarks they have no external
URL and no archives — the note body *is* the content.

> **`private` defaults to `true` for notes**, the opposite of bookmarks. If you
> want a note to be publicly visible you must say so explicitly.

### Viewing a note

```
GET /notes/:id.json
GET /notes/:id.md
```

No key needed for a public note. A private one needs `read:notes`, otherwise `404`.

**`.md` returns the note as a raw Markdown document** — title as a heading, tags,
then the body:

```bash
curl -H "Authorization: Bearer $BB_KEY" \
     "http://localhost:3334/notes/69dd541fb1a9dabdb5ad3e29.md"
```

```markdown
# Jabberwocky

#poetry #victorian

’Twas brillig, and the slithy toves
Did gyre and gimble in the wabe…
```

The title heading and the tag line are omitted when the note has no title or no
tags, so a bare note returns just its body.

`.json` returns the record:

```json
{
  "id": "69dd541fb1a9dabdb5ad3e29",
  "title": "Jabberwocky",
  "string_data": "’Twas brillig, and the slithy toves…",
  "tags": ["poetry", "victorian"],
  "mime_type": "text/markdown",
  "created_at": "2026-01-02T03:04:05.000Z",
  "updated_at": "2026-01-02T03:04:05.000Z",
  "app_url": "http://localhost:3334/notes/69dd541fb1a9dabdb5ad3e29",
  "private": true,
  "sensitive": false
}
```

### Creating a note

```
POST /notes.json
```

Requires `write:notes`.

```bash
curl -X POST "http://localhost:3334/notes.json" \
     -H "Authorization: Bearer $BB_KEY" \
     -H "Content-Type: application/json" \
     -d '{
           "note": {
             "string_data": "’Twas brillig, and the slithy toves",
             "title": "Jabberwocky",
             "tags": ["poetry", "victorian"],
             "private": false
           }
         }'
```

| Field | Type | Notes |
|---|---|---|
| `string_data` | string | **Required.** The note body, as Markdown. |
| `title` | string | Optional — **unless `sensitive` is `true`**, where it's required, so there's something unblurred to show. |
| `tags` | array of strings, or a string | See "Tag formats" below. |
| `private` | boolean | **Defaults to `true`.** |
| `sensitive` | boolean | Defaults to `false`. Blurs the note in the UI. |

Responds `201 Created` with the note, or `422` with `{"errors": {...}}`.

### Updating a note

```
PATCH /notes/:id.json
PUT   /notes/:id.json
```

Requires `write:notes`. Send only the fields you want changed:

```bash
curl -X PATCH "http://localhost:3334/notes/69dd541fb1a9dabdb5ad3e29.json" \
     -H "Authorization: Bearer $BB_KEY" \
     -H "Content-Type: application/json" \
     -d '{"note": {"string_data": "…And the mome raths outgrabe."}}'
```

Responds `200 OK`, or `422` with `{"errors": {...}}`. As with bookmarks, `tags`
replaces the whole list.

---

## MCP server

BackupBrain is also an [MCP](https://modelcontextprotocol.io) (Model Context
Protocol) server, so AI agents and the tools built around them can search your
knowledge base and read what they find. It speaks the **Streamable HTTP**
transport at:

```
POST /mcp
```

It uses the same API keys and permission scopes as the rest of this document.
Every request needs a key; there is no anonymous access to the MCP server.
For a step by step setup guide aimed at end users, see
[accessing_your_data_with_agents.md](accessing_your_data_with_agents.md).

### Connecting a client

Most MCP clients take a URL plus headers. For example, in Claude Code:

```bash
claude mcp add --transport http backup_brain http://localhost:3334/mcp \
  --header "Authorization: Bearer $BB_KEY"
```

or as JSON in a client's configuration file:

```json
{
  "mcpServers": {
    "backup_brain": {
      "type": "http",
      "url": "http://localhost:3334/mcp",
      "headers": {"Authorization": "Bearer $BB_KEY"}
    }
  }
}
```

A client that only speaks the stdio transport can bridge to it with
[`mcp-remote`](https://www.npmjs.com/package/mcp-remote):

```
npx mcp-remote http://localhost:3334/mcp --header "Authorization: Bearer $BB_KEY"
```

The server is stateless: no sessions, no server-initiated messages. `GET` and
`DELETE` on `/mcp` answer `405`. A missing, unknown or expired key answers `401`
before any MCP message is read.

### Tools

| Tool | Needs | Does |
|---|---|---|
| `search` | `read:bookmarks` and/or `read:notes` | Full text search. Returns summaries, not bodies. |
| `get_bookmark` | `read:bookmarks` | A bookmark, the Markdown of its latest archive, and its latest transcription. |
| `get_note` | `read:notes` | The full Markdown of a note. |
| `create_note` | `write:notes` | Saves a new note. |

Permissions are checked per tool call. `search` only searches the record types
the key can read, and names the ones it couldn't under `denied`, so a key with
only `read:notes` still gets note results. The other tools return an MCP tool
error naming the missing permission. People, reviews and other record types are
not exposed.

Every tool answers with one `text` content block containing JSON.

**`search`** — `query` (required; `#hashtags` in it become tag filters), `types`
(`["bookmarks", "notes"]`, default both), `tags` (records must carry all of
them), `search_archives` (default `false`: bookmarks are matched on title,
description, url and tags only), `limit` (per type, default 20, max 100).
Results come back in Meilisearch's relevance order.

```json
{
  "query": "brillig",
  "tags": [],
  "denied": [],
  "bookmarks": [
    {
      "type": "bookmark",
      "id": "69dd541fb1a9dabdb5ad3e29",
      "title": "Jabberwocky",
      "url": "https://example.com/jabberwocky",
      "description": "a poem",
      "tags": ["poetry"],
      "private": false,
      "has_archive": true,
      "has_transcription": false,
      "created_at": "2026-10-31T12:00:00Z",
      "app_url": "http://localhost:3334/bookmarks/69dd541fb1a9dabdb5ad3e29"
    }
  ],
  "notes": [
    {
      "type": "note",
      "id": "69dd54a0b1a9dabdb5ad3e2a",
      "title": "Toves",
      "excerpt": "slithy and gyre…",
      "tags": ["poetry"],
      "private": true,
      "created_at": "2026-10-31T12:00:00Z",
      "updated_at": "2026-10-31T12:00:00Z",
      "app_url": "http://localhost:3334/notes/69dd54a0b1a9dabdb5ad3e2a"
    }
  ]
}
```

**`get_bookmark`** — `id` (required), `include_archive` and
`include_transcription` (default `true`), `max_characters` (cuts the archive and
the transcription down to that many characters each; `truncated` says whether
anything was cut). Only the most recent Markdown archive and the most recent
completed transcription are returned; older ones aren't available over MCP.
Transcription text has its timestamps stripped.

```json
{
  "id": "69dd541fb1a9dabdb5ad3e29",
  "title": "Jabberwocky",
  "url": "https://example.com/jabberwocky",
  "description": "a poem",
  "tags": ["poetry"],
  "private": false,
  "sensitive": false,
  "to_read": false,
  "created_at": "2026-10-31T12:00:00Z",
  "app_url": "http://localhost:3334/bookmarks/69dd541fb1a9dabdb5ad3e29",
  "archive": {
    "mime_type": "text/markdown",
    "created_at": "2026-10-31T12:00:05Z",
    "manually_edited": false,
    "truncated": false,
    "markdown": "# Jabberwocky\n\n'Twas brillig…"
  },
  "transcription": {
    "source": "whisper",
    "media_url": "/archives/bookmarks/69dd541fb1a9dabdb5ad3e29/abc123.mp3",
    "media_type": "audio",
    "created_at": "2026-10-31T12:10:00Z",
    "truncated": false,
    "text": "Twas brillig and the slithy toves…"
  }
}
```

`archive` and `transcription` are `null` when there isn't one. An id the key
can't read, for any reason, is reported as not found.

**`get_note`** — `id` (required). Returns `id`, `title`, `tags`, `private`,
`sensitive`, `mime_type`, timestamps, `app_url` and the full `markdown`.

**`create_note`** — `markdown` (required), `title`, `tags`, `private` (default
`true`), `sensitive` (default `false`; needs a `title`). Returns the new note's
`id`, `title`, `tags`, flags and `app_url`. Validation failures come back as a
tool error.

---

## Quirks & gotchas

**Tag formats.** `tags` accepts either an array (`["poetry", "victorian"]`) or a
comma/space-separated string (`"poetry, victorian"`). Either way tags are
normalised: lowercased, with internal whitespace replaced by underscores. `"Sci
Fi"` becomes `sci_fi`. Tags may not contain commas.

**`GET /bookmarks/:id.json` has a different shape from search results.** It's the
raw database document — `_id` rather than `id`, no `app_url`, and extra internal
fields like `user_id` and `person_ids`. Search results are a curated view. Don't
assume the two are interchangeable.

**Search needs Meilisearch; the record endpoints don't.** If `SEARCH_ENABLED` is
false or Meilisearch is down, search returns `502` while everything else keeps
working.

**Search results are capped at 10,000** and are not paginated in raw formats. A
query matching more than that is silently truncated. Narrow it with tags.

**Search result ordering.** With `sort=newest` results are ordered by creation
date. With the default `sort=match`, the raw formats return records in database
order rather than strict relevance order — treat `match` as a filter, not a ranking,
if order matters to you.

**Deleting is not available over the API.** `DELETE` on either collection still
requires a browser session.

**Keys are stored in plain text** in the database, and are not hashed. Anyone with
read access to your MongoDB has your keys. Set expiration dates on keys you hand to
anything you don't fully control, and delete keys you're done with.

**Expiry is date-based**, not time-based. A key expires at the start of the day
*after* its expiration date — a key dated today still works today.
