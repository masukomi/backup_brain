# Accessing your data with agents

BackupBrain can act as an [MCP](https://modelcontextprotocol.io) (Model Context
Protocol) server. That lets AI agents and the tools built around them (Claude
Code, Claude Desktop, Blackwell, and anything else that speaks MCP) search your
bookmarks and notes, read the archived copies of pages you've bookmarked, read
transcriptions of archived audio and video, and, if you allow it, save new
notes.

This guide walks through turning that on for one agent. It takes about five
minutes.

- [What an agent can do](#what-an-agent-can-do)
- [Step 1: create an API key](#step-1-create-an-api-key)
- [Step 2: find your MCP URL](#step-2-find-your-mcp-url)
- [Step 3: connect your agent](#step-3-connect-your-agent)
- [Step 4: check that it works](#step-4-check-that-it-works)
- [Step 5 (optional): teach the agent when to use it](#step-5-optional-teach-the-agent-when-to-use-it)
- [Revoking access](#revoking-access)
- [Privacy and safety](#privacy-and-safety)
- [Troubleshooting](#troubleshooting)

---

## What an agent can do

The MCP server exposes four tools:

| Tool | What it does | Permission it needs |
|---|---|---|
| `search` | Full text search of bookmarks and notes. Returns summaries: title, original url, description, tags, and whether an archive or transcription exists. | `read:bookmarks` and/or `read:notes` |
| `get_bookmark` | One bookmark, the Markdown of its most recent archive, and the most recent transcription of its archived audio or video. | `read:bookmarks` |
| `get_note` | The full Markdown of one note. | `read:notes` |
| `create_note` | Saves a new note. | `write:notes` |

Nothing else is exposed. Agents can't see people, reviews, settings or
credentials, and they can't edit or delete anything.

Every tool checks the permissions of the key that made the call, so what an
agent can reach is entirely decided by the key you give it.

---

## Step 1: create an API key

1. Sign in to BackupBrain and go to **Access Keys** (`/access`).
2. Under **API Keys**, click **New API Key**.
3. Give it a **name** that tells you which agent it's for, e.g. `Blackwell on
   the laptop`. You'll want this later when deciding which key to revoke.
4. Set an **expiration date** if the agent is something you don't fully trust or
   control. You can always make a new key. Leave it blank for a key that never
   expires.
5. Tick the **permissions** the agent needs (see below).
6. Click create. The key is shown **once**, on the next page. Copy it somewhere
   safe now; there is no way to see it again. If you lose it, delete the key and
   make another.

### Which permissions to grant

**For reading, grant both of these.** Without them the agent gets nothing
useful back:

| Permission | Lets the agent |
|---|---|
| `read:bookmarks` | Search bookmarks, including private ones, and read their archives and transcriptions |
| `read:notes` | Search and read notes, including private ones |

You can grant only one of them. A key with just `read:notes` can still search,
but bookmarks will be left out of the results and the response will say so.

**If you want the agent to be able to save notes**, also grant:

| Permission | Lets the agent |
|---|---|
| `write:notes` | Create new notes (private by default). It cannot edit or delete existing ones. |

This is handy for a research agent that should file what it found, or for
dictating notes through an assistant. If you don't need it, leave it off; a
read-only key can't change anything in your knowledge base.

Leave every other permission unticked. The MCP server doesn't use them, and a
key should carry no more than it needs.

> **A key is you.** BackupBrain is a single-user system. A key with
> `read:notes` sees *all* your notes, including private ones, exactly as you
> would when signed in. There is no "public only" key. Think of a key as a copy
> of your login limited to the ticked collections, and treat it with the same
> care. The "hide private" toggle in the web UI does not apply to keys.

---

## Step 2: find your MCP URL

The MCP endpoint is `/mcp` on your BackupBrain instance:

| Where BackupBrain runs | MCP URL |
|---|---|
| The same computer as the agent, default port | `http://localhost:3334/mcp` |
| Another machine on your network or tailnet | `http://<host>:3334/mcp` |
| Behind HTTPS (reverse proxy, Tailscale Funnel, etc.) | `https://<your-host>/mcp` |

If the agent and BackupBrain are on different machines, use HTTPS or a private
network such as Tailscale. The key travels in a header on every request, and
plain HTTP across the open internet would expose it.

---

## Step 3: connect your agent

Every MCP client needs the same two things: the URL and an `Authorization`
header carrying the key. Replace `YOUR_KEY` below with the key from step 1.

### Claude Code

```bash
claude mcp add --transport http backup_brain http://localhost:3334/mcp \
  --header "Authorization: Bearer YOUR_KEY"
```

Add `--scope user` to make it available in every project rather than just the
current one.

### Claude Desktop, Cursor, and other clients with a JSON config

Most clients accept an entry like this in their MCP configuration file (Claude
Desktop: *Settings → Developer → Edit Config*):

```json
{
  "mcpServers": {
    "backup_brain": {
      "type": "http",
      "url": "http://localhost:3334/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_KEY"
      }
    }
  }
}
```

Some clients call the transport `"streamable-http"` or `"streamableHttp"`
instead of `"http"`. Check your client's documentation if the entry above isn't
picked up.

### Clients that only support stdio

Older clients, and some that insist on launching a local process, can reach
BackupBrain through [`mcp-remote`](https://www.npmjs.com/package/mcp-remote),
which bridges stdio to HTTP. Point the client at this command:

```
npx mcp-remote http://localhost:3334/mcp --header "Authorization: Bearer YOUR_KEY"
```

As a JSON config entry:

```json
{
  "mcpServers": {
    "backup_brain": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://localhost:3334/mcp",
        "--header",
        "Authorization: Bearer YOUR_KEY"
      ]
    }
  }
}
```

### Blackwell

Blackwell takes MCP servers the same way as Claude Code: add the `backup_brain`
server with the URL and header above, then ask it to search BackupBrain before
it searches the web. Its own tool descriptions tell it to start with `search`
and only fetch full archives for the matches it cares about, so it won't pull
your whole knowledge base into its context.

---

## Step 4: check that it works

Ask the agent something you know is in BackupBrain, e.g. *"search my
BackupBrain for anything about sourdough"*, and it should call the `search`
tool and come back with your bookmarks and notes.

To check the server without an agent, send it a ping with `curl`:

```bash
curl -s http://localhost:3334/mcp \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"ping"}'
```

A working server answers `{"jsonrpc":"2.0","id":1,"result":{}}`. A `401`
means the key is missing, mistyped or expired.

---

## Step 5 (optional): teach the agent when to use it

The server tells agents *how* to use each tool. It can't tell them *when* to
reach for BackupBrain instead of the web, or how you like notes filed. For
that, BackupBrain ships a skill: a short Markdown file that agents supporting
the [Agent Skills](https://agentskills.io) format (Claude Code, Blackwell and
others) read to decide when the server is relevant.

It lives at [`skills/backup_brain/SKILL.md`](skills/backup_brain/SKILL.md)
in the BackupBrain repository. It tells the agent to search BackupBrain before
researching on the web, to look there whenever you ask about something you've
saved or read, to search metadata before archives, to keep large archives out
of its context, and to only create notes when you ask, tagged `agent_created`
and left private.

To install it for Claude Code, copy the folder into your skills directory:

```bash
mkdir -p ~/.claude/skills
cp -r /path/to/backup_brain/skills/backup_brain ~/.claude/skills/
```

Use a project's `.claude/skills/` directory instead to limit it to one project.
Other agents have their own skills directory; check their documentation.

The file is plain Markdown, so edit it to match your habits: the tags you
want on agent-written notes, topics you'd rather the agent didn't search for,
or a reminder that your audio bookmarks usually have transcripts worth reading.

---

## Revoking access

Go to **Access Keys** (`/access`), find the key by name, and delete it. The
agent loses access immediately; nothing else changes. If you only want to
change what an agent can do, delete its key and create a new one with
different permissions, then update the agent's configuration.

---

## Privacy and safety

- **Private records are visible to any key that can read their collection.**
  If there are notes or bookmarks you never want an agent to see, keep them in
  a collection the key can't read, or don't connect an agent at all.
- **Anything the agent reads may leave your machine.** Most agents send what
  they read to a hosted model. Archived pages and transcriptions go along for
  the ride. Only connect agents whose data handling you're comfortable with.
- **Agents can't delete or edit.** The worst a key with `write:notes` can do is
  create notes. The worst a read-only key can do is read.
- **Set an expiry on keys you hand to anything you don't control.** Keys are
  stored in plain text in the database, like every other API key in
  BackupBrain. Anyone with your MongoDB has them.
- **One key per agent.** When something goes wrong you can revoke one without
  disturbing the rest, and the key's name tells you which agent did what.

---

## Troubleshooting

**`401 Unauthorized`.** The key is missing, mistyped, deleted or past its
expiration date. Check the `Authorization` header is exactly
`Bearer YOUR_KEY`, with a space after `Bearer`.

**Search returns nothing but the agent can fetch a bookmark by id.** Search
needs Meilisearch. Check that `SEARCH_ENABLED` is on and Meilisearch is
running. The tool returns an error naming the problem when Meilisearch is
unreachable.

**Search results list `denied` permissions.** The key lacks `read:bookmarks` or
`read:notes`. Make a new key with both.

**`create_note` says it lacks a permission.** The key needs `write:notes`.
Write permissions are separate from read permissions; one does not imply the
other.

**The client says the server needs a session, or complains about GET.** The
BackupBrain MCP server is stateless and answers `405` to `GET` and `DELETE`,
which the MCP specification allows. Any current client copes with this. If
yours doesn't, the `mcp-remote` bridge above will.

**A bookmark's `transcription` is `null` even though it has audio.** Only
completed transcriptions are returned. Check the bookmark in the web UI; the
transcription may still be processing, may have failed, or transcription may be
disabled in Settings.

For the exact shape of every tool's input and output, see the
[MCP section of the API documentation](api_documentation.md#mcp-server).
