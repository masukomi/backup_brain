require "rails_helper"

# Covers the MCP (Model Context Protocol) server at /mcp: key
# authentication, the tools it lists, and what each tool answers.
RSpec.describe "MCP server", type: :request do
  let(:user) { User.first || create(:user) }
  let(:read_write) { create(:api_key) }
  let(:read_only) { create(:read_only_api_key) }
  let(:notes_only) { create(:notes_only_api_key) }
  let(:bookmarks_only) { ApiKey.create!(name: "bookmarks only", permissions: ["read:bookmarks"]) }

  def headers(key)
    {
      "Authorization" => "Bearer #{key.key}",
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
  end

  def rpc(method, params = {}, key: read_write)
    body = {jsonrpc: "2.0", id: 1, method: method, params: params}.to_json
    post "/mcp", params: body, headers: headers(key)
    response.parsed_body
  end

  # calls a tool and returns the parsed JSON it answered with
  def call_tool(name, arguments, key: read_write)
    result = rpc("tools/call", {name: name, arguments: arguments}, key: key)["result"]
    text = result["content"].first["text"]
    result["isError"] ? {"error" => text} : JSON.parse(text)
  end

  def search_results_for(klass, records)
    allow(klass).to receive(:search).and_return(
      {"matches" => records.map { |r| r.id.to_s },
       "search_result_metadata" => {"nbHits" => records.size}}
    )
  end

  # rubocop:disable RSpec/AnyInstance
  before do
    [Bookmark, Note].each do |klass|
      allow_any_instance_of(klass).to receive(:add_to_search)
      allow_any_instance_of(klass).to receive(:update_in_search)
      allow_any_instance_of(klass).to receive(:remove_from_search)
    end
    # don't try to archive example.com during tests
    allow_any_instance_of(Bookmark).to receive(:generate_archive)
    allow_any_instance_of(MediaObject).to receive(:transcribe)
  end
  # rubocop:enable RSpec/AnyInstance

  after do
    Bookmark.destroy_all
    Note.destroy_all
    Tag.destroy_all
    ApiKey.destroy_all
    User.destroy_all
  end

  let(:bookmark) do
    Bookmark.create!(url: "https://example.com/j", title: "Jabberwocky",
      description: "a poem", tags: %w[poetry], private: true, user: user)
  end

  # a bookmark with an archive whose audio has been transcribed
  let(:transcribed_bookmark) do
    archive = bookmark.archives.create!(string_data: "# Jabberwocky\n\nTwas brillig")
    media = archive.media_objects.create!(url: "/archives/bookmarks/#{bookmark.id}/abc.mp3", simple_type: "audio")
    media.create_transcription(text: "0:00 twas brillig\n0:05 and the slithy toves", status: "completed", source: "whisper")
    bookmark.reload
  end

  let(:note) { Note.create!(title: "Toves", string_data: "slithy and gyre", tags: %w[poetry], private: true) }

  describe "authentication" do
    it "rejects a request with no key" do
      post "/mcp", params: {jsonrpc: "2.0", id: 1, method: "ping"}.to_json,
        headers: {"Content-Type" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an unknown key" do
      post "/mcp", params: {jsonrpc: "2.0", id: 1, method: "ping"}.to_json,
        headers: {"Authorization" => "Bearer nope", "Content-Type" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired key" do
      rpc("ping", key: create(:expired_api_key))

      expect(response).to have_http_status(:unauthorized)
    end

    it "answers a ping with a valid key" do
      expect(rpc("ping")["result"]).to eq({})
    end

    it "doesn't stream (GET)" do
      get "/mcp", headers: headers(read_write)

      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe "initialize" do
    it "identifies the server" do
      result = rpc("initialize", {protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: "spec", version: "0"}})["result"]

      expect(result.dig("serverInfo", "name")).to eq("backup_brain")
    end
  end

  describe "tools/list" do
    it "lists the tools" do
      names = rpc("tools/list")["result"]["tools"].map { |t| t["name"] }

      expect(names).to contain_exactly("search", "get_bookmark", "get_note", "create_note")
    end

    # The mcp gem fills in destructiveHint: true whenever it's omitted, and
    # some clients (Paperclip) trust that over readOnlyHint.
    it "marks the read-only tools as non-destructive" do
      tools = rpc("tools/list")["result"]["tools"]
      readers = tools.select { |t| t["annotations"]["readOnlyHint"] }

      expect(readers.map { |t| [t["name"], t["annotations"]["destructiveHint"]] })
        .to contain_exactly(["search", false], ["get_bookmark", false], ["get_note", false])
    end
  end

  describe "search" do
    before do
      transcribed_bookmark
      search_results_for(Bookmark, [bookmark])
      search_results_for(Note, [note])
    end

    context "with a key that reads both" do
      let(:result) { call_tool("search", {query: "brillig"}) }
      let(:first_bookmark) { result["bookmarks"].first }

      it "returns the bookmark's original url" do
        expect(first_bookmark["url"]).to eq("https://example.com/j")
      end

      it "says whether an archive exists" do
        expect(first_bookmark["has_archive"]).to be(true)
      end

      it "says whether a transcription exists" do
        expect(first_bookmark["has_transcription"]).to be(true)
      end

      it "includes the title, description and tags" do
        expect(first_bookmark.slice("title", "description", "tags"))
          .to eq("title" => "Jabberwocky", "description" => "a poem", "tags" => ["poetry"])
      end

      it "returns notes" do
        expect(result["notes"].first["title"]).to eq("Toves")
      end

      it "denies nothing" do
        expect(result["denied"]).to be_empty
      end
    end

    it "only searches the types asked for" do
      result = call_tool("search", {query: "brillig", types: ["notes"]})

      expect(result).not_to have_key("bookmarks")
    end

    it "sends hashtags in the query to Meilisearch as a tag filter" do
      call_tool("search", {query: "brillig #poetry"})

      expect(Bookmark).to have_received(:search)
        .with("brillig", hash_including(options: hash_including(filter: "tags IN [poetry]")))
    end

    it "only matches bookmark metadata unless asked to search archives" do
      call_tool("search", {query: "brillig"})

      expect(Bookmark).to have_received(:search)
        .with("brillig", hash_including(options: hash_including(attributes_to_search_on: %w[title description tags url])))
    end

    it "searches archives when asked" do
      call_tool("search", {query: "brillig", search_archives: true})

      expect(Bookmark).to have_received(:search)
        .with("brillig", hash_including(options: hash_excluding(:attributes_to_search_on)))
    end

    context "with a key that can only read notes" do
      let(:result) { call_tool("search", {query: "brillig"}, key: notes_only) }

      it "reports the bookmark permission it lacks" do
        expect(result["denied"]).to eq(["read:bookmarks"])
      end

      it "omits bookmarks entirely" do
        expect(result).not_to have_key("bookmarks")
      end

      it "still returns notes" do
        expect(result["notes"].size).to eq(1)
      end
    end

    it "complains about an empty query" do
      result = call_tool("search", {query: "   "})

      expect(result).to have_key("error")
    end

    it "reports Meilisearch being down as an error" do
      allow(Bookmark).to receive(:search).and_raise(MeiliSearch::ApiError.new(502, "down", nil))

      expect(call_tool("search", {query: "brillig", types: ["bookmarks"]})).to have_key("error")
    end
  end

  describe "get_bookmark" do
    context "with a read key" do
      let(:result) { call_tool("get_bookmark", {id: transcribed_bookmark.id.to_s}) }

      it "returns the archived markdown" do
        expect(result.dig("archive", "markdown")).to include("Twas brillig")
      end

      it "returns the transcription without timestamps" do
        expect(result.dig("transcription", "text")).to eq("twas brillig\nand the slithy toves")
      end

      it "names the transcribed media" do
        expect(result.dig("transcription", "media_url")).to end_with("abc.mp3")
      end

      it "returns the original url" do
        expect(result["url"]).to eq("https://example.com/j")
      end
    end

    it "can leave the archive out" do
      result = call_tool("get_bookmark", {id: transcribed_bookmark.id.to_s, include_archive: false})

      expect(result["archive"]).to be_nil
    end

    it "truncates to max_characters" do
      result = call_tool("get_bookmark", {id: transcribed_bookmark.id.to_s, max_characters: 5})

      expect(result["archive"].slice("markdown", "truncated")).to eq("markdown" => "# Jab", "truncated" => true)
    end

    it "returns null archive and transcription for an unarchived bookmark" do
      result = call_tool("get_bookmark", {id: bookmark.id.to_s})

      expect(result.values_at("archive", "transcription")).to eq([nil, nil])
    end

    it "is forbidden to a key without read:bookmarks" do
      result = call_tool("get_bookmark", {id: bookmark.id.to_s}, key: notes_only)

      expect(result["error"]).to include("read:bookmarks")
    end

    it "reports an unknown id as not found" do
      expect(call_tool("get_bookmark", {id: "nope"})).to have_key("error")
    end
  end

  describe "get_note" do
    it "returns the full markdown" do
      expect(call_tool("get_note", {id: note.id.to_s})["markdown"]).to eq("slithy and gyre")
    end

    it "is forbidden to a key without read:notes" do
      result = call_tool("get_note", {id: note.id.to_s}, key: bookmarks_only)

      expect(result["error"]).to include("read:notes")
    end

    it "reports an unknown id as not found" do
      expect(call_tool("get_note", {id: BSON::ObjectId.new.to_s})).to have_key("error")
    end
  end

  describe "create_note" do
    let(:arguments) { {markdown: "a new note", title: "New", tags: ["Sci_Fi", "gamma"]} }

    context "with a write key" do
      let!(:result) { call_tool("create_note", arguments) }

      it "creates the note" do
        expect(Note.find(result["id"]).string_data).to eq("a new note")
      end

      it "normalizes the tags" do
        expect(result["tags"]).to contain_exactly("sci_fi", "gamma")
      end

      it "is private by default" do
        expect(result["private"]).to be(true)
      end

      it "links to the note" do
        expect(result["app_url"]).to eq("http://www.example.com/notes/#{result["id"]}")
      end
    end

    it "can create a public note" do
      result = call_tool("create_note", arguments.merge(private: false))

      expect(result["private"]).to be(false)
    end

    it "is forbidden to a read-only key" do
      result = call_tool("create_note", arguments, key: read_only)

      expect(result["error"]).to include("write:notes")
    end

    it "reports validation errors" do
      result = call_tool("create_note", {markdown: "untitled but sensitive", sensitive: true})

      expect(result["error"]).to include("Title")
    end

    it "rejects a call missing the markdown" do
      result = rpc("tools/call", {name: "create_note", arguments: {title: "nothing"}})["result"]

      expect(result["isError"]).to be(true)
    end
  end
end
