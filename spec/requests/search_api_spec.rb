require "rails_helper"

# Covers the raw (json & md) search formats, which require an API key,
# and confirms the html path is unaffected by them.
RSpec.describe "Search API", type: :request do
  let(:query) { "brillig" }
  # Bookmark belongs_to :user
  let(:user) { User.first || create(:user) }

  # the shape mongodb_meilisearch returns for ids_only searches
  def search_results(ids)
    {
      "matches"                => ids.map(&:to_s),
      "search_result_metadata" => {"nbHits" => ids.size}
    }
  end

  def stub_search(klass, ids)
    allow(klass).to receive(:search).and_return(search_results(ids))
  end

  def auth(key)
    {"Authorization" => "Bearer #{key}"}
  end

  # rubocop:disable RSpec/AnyInstance
  before do
    # keep Meilisearch out of the model callbacks
    [Bookmark, Note].each do |klass|
      allow_any_instance_of(klass).to receive(:add_to_search)
      allow_any_instance_of(klass).to receive(:update_in_search)
      allow_any_instance_of(klass).to receive(:remove_from_search)
    end
  end
  # rubocop:enable RSpec/AnyInstance

  after do
    Bookmark.destroy_all
    Note.destroy_all
    Tag.destroy_all
    ApiKey.destroy_all
    User.destroy_all
  end

  describe "authentication" do
    let!(:note) { Note.create!(string_data: "Twas brillig", private: false) }

    before { stub_search(Note, [note.id]) }

    context "when there is no Authorization header" do
      before { get "/notes/search.json", params: {query: query} }

      it "responds with unauthorized" do
        expect(response).to have_http_status(:unauthorized)
      end

      it "explains that a key is required" do
        expect(response.parsed_body["error"]).to eq(I18n.t("api.errors.missing_key"))
      end

      it "advertises the expected scheme" do
        expect(response.headers["WWW-Authenticate"]).to include("Bearer")
      end
    end

    context "when the key is unknown" do
      before { get "/notes/search.json", params: {query: query}, headers: auth("not-a-real-key") }

      it "responds with unauthorized" do
        expect(response).to have_http_status(:unauthorized)
      end

      it "says the key is invalid" do
        expect(response.parsed_body["error"]).to eq(I18n.t("api.errors.invalid_key"))
      end
    end

    it "rejects an expired key" do
      key = create(:expired_api_key, permissions: ["read:notes"])

      get "/notes/search.json", params: {query: query}, headers: auth(key.key)

      expect(response).to have_http_status(:unauthorized)
    end

    context "when the key lacks the matching read permission" do
      before do
        key = create(:notes_only_api_key)
        bookmark = Bookmark.create!(url: "https://example.com/a", title: "A", user: user)
        stub_search(Bookmark, [bookmark.id])

        get "/bookmarks/search.json", params: {query: query}, headers: auth(key.key)
      end

      it "responds with forbidden" do
        expect(response).to have_http_status(:forbidden)
      end

      it "names the permission it wanted" do
        expect(response.parsed_body["error"]).to include("read:bookmarks")
      end
    end

    it "accepts a key with the matching read permission" do
      key = create(:notes_only_api_key)

      get "/notes/search.json", params: {query: query}, headers: auth(key.key)

      expect(response).to have_http_status(:ok)
    end

    context "when an md request fails to authenticate" do
      before { get "/notes/search.md", params: {query: query} }

      it "responds with unauthorized" do
        expect(response).to have_http_status(:unauthorized)
      end

      it "answers in markdown rather than json" do
        expect(response.media_type).to eq("text/markdown")
      end

      it "still explains the problem" do
        expect(response.body).to include(I18n.t("api.errors.missing_key"))
      end
    end
  end

  describe "json results" do
    let!(:public_note)  { Note.create!(title: "public", string_data: "Twas brillig", private: false) }
    let!(:private_note) { Note.create!(title: "secret", string_data: "brillig too",  private: true) }
    let(:key) { create(:notes_only_api_key) }

    before { stub_search(Note, [public_note.id, private_note.id]) }

    context "with a valid key" do
      before { get "/notes/search.json", params: {query: query}, headers: auth(key.key) }

      it "succeeds" do
        expect(response).to have_http_status(:ok)
      end

      it "echoes the query" do
        expect(response.parsed_body["query"]).to eq(query)
      end

      it "reports the total it is returning" do
        expect(response.parsed_body["total"]).to eq(2)
      end

      it "returns private records alongside public ones" do
        expect(response.parsed_body["results"].pluck("title"))
          .to contain_exactly("public", "secret")
      end

      it "includes the fields an api consumer needs" do
        expect(response.parsed_body["results"].first.keys)
          .to include("id", "title", "string_data", "tags", "private")
      end
    end

    it "asks Meilisearch for everything at once rather than a page" do # rubocop:disable RSpec/MultipleExpectations
      expect(Note).to receive(:search).at_least(:once) do |_query, options:, **_rest|
        expect(options[:limit]).to eq(ApplicationController::RAW_RESULT_CAP)
        expect(options[:offset]).to eq(0)
        # a valid key sees private records, so there's no privacy filter
        expect(options[:filter]).to be_blank
        search_results([public_note.id])
      end

      get "/notes/search.json", params: {query: query}, headers: auth(key.key)
    end

    context "when the query is blank" do
      before { get "/notes/search.json", params: {query: ""}, headers: auth(key.key) }

      it "responds with bad request rather than a redirect" do
        expect(response).to have_http_status(:bad_request)
      end

      it "says what was missing" do
        expect(response.parsed_body["error"]).to eq(I18n.t("search.missing_query"))
      end
    end
  end

  describe "markdown results" do
    let!(:bookmark) do
      Bookmark.create!(url: "https://example.com/jabberwocky",
        title: "Jabberwocky",
        description: "Twas brillig",
        tags: ["poetry"],
        user: user)
    end
    let(:key) { create(:api_key) }

    before do
      stub_search(Bookmark, [bookmark.id])
      get "/bookmarks/search.md", params: {query: query}, headers: auth(key.key)
    end

    it "succeeds" do
      expect(response).to have_http_status(:ok)
    end

    it "is served as markdown" do
      expect(response.media_type).to eq("text/markdown")
    end

    it "heads the document with the query" do
      expect(response.body).to include("# #{I18n.t("search.markdown.heading", query: query)}")
    end

    it "links each result from its title" do
      expect(response.body).to include("## [Jabberwocky](https://example.com/jabberwocky)")
    end

    it "lists the tags" do
      expect(response.body).to include("#poetry")
    end

    it "includes the description" do
      expect(response.body).to include("Twas brillig")
    end
  end

  describe "the html path" do
    let!(:note) { Note.create!(string_data: "Twas brillig", private: false) }

    before { stub_search(Note, [note.id]) }

    context "with no api key at all" do
      before { get "/notes/search", params: {query: query} }

      it "still succeeds" do
        expect(response).to have_http_status(:ok)
      end

      it "still renders html" do
        expect(response.media_type).to eq("text/html")
      end
    end

    it "still hides private records from anonymous visitors" do # rubocop:disable RSpec/MultipleExpectations
      expect(Note).to receive(:search).at_least(:once) do |_query, options:, **_rest|
        expect(options[:filter]).to include("private = false")
        search_results([note.id])
      end

      get "/notes/search", params: {query: query}
    end

    it "still redirects a blank query" do
      get "/notes/search", params: {query: ""}

      expect(response).to have_http_status(:redirect)
    end
  end
end
