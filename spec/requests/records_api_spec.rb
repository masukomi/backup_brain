require "rails_helper"

# Covers the key-authenticated record endpoints: viewing a bookmark's
# latest archive, viewing a note, and creating / updating both.
RSpec.describe "Records API", type: :request do
  let(:user) { User.first || create(:user) }
  let(:read_write) { create(:api_key) }
  let(:read_only)  { create(:read_only_api_key) }

  def auth(key)
    {"Authorization" => "Bearer #{key.key}", "Content-Type" => "application/json"}
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
  end
  # rubocop:enable RSpec/AnyInstance

  after do
    Bookmark.destroy_all
    Note.destroy_all
    Tag.destroy_all
    ApiKey.destroy_all
    User.destroy_all
  end

  describe "GET a note" do
    let(:note) { Note.create!(title: "Jabberwocky", string_data: "Twas brillig", tags: ["poetry"], private: true) }

    context "with a read key, as markdown" do
      before { get "/notes/#{note.id}.md", headers: auth(read_write) }

      it "succeeds" do
        expect(response).to have_http_status(:ok)
      end

      it "is served as markdown" do
        expect(response.media_type).to eq("text/markdown")
      end

      it "includes the body" do
        expect(response.body).to include("Twas brillig")
      end

      it "includes the tags" do
        expect(response.body).to include("#poetry")
      end
    end

    it "returns the note as json with a read key" do
      get "/notes/#{note.id}.json", headers: auth(read_write)

      expect(response.parsed_body["string_data"]).to eq("Twas brillig")
    end

    it "hides a private note from an anonymous caller" do
      get "/notes/#{note.id}.json"

      expect(response).to have_http_status(:not_found)
    end

    it "serves a public note to an anonymous caller" do
      public_note = Note.create!(string_data: "open", private: false)

      get "/notes/#{public_note.id}.json"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET a bookmark" do
    let(:bookmark) do
      Bookmark.create!(url: "https://example.com/j", title: "J", private: true, user: user)
    end

    it "hides a private bookmark from an anonymous caller" do
      get "/bookmarks/#{bookmark.id}.json"

      expect(response).to have_http_status(:not_found)
    end

    it "serves a private bookmark to a read key" do
      get "/bookmarks/#{bookmark.id}.json", headers: auth(read_write)

      expect(response).to have_http_status(:ok)
    end

    it "serves a public bookmark to an anonymous caller" do
      public_bookmark = Bookmark.create!(url: "https://example.com/p", title: "P", private: false, user: user)

      get "/bookmarks/#{public_bookmark.id}.json"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /bookmarks.json" do
    let(:payload) { {bookmark: {url: "https://example.com/new", title: "New", tags: %w[alpha beta]}} }

    context "with a write key" do
      before do
        user # the single-user instance has to exist for the bookmark to belong to
        post "/bookmarks.json", params: payload.to_json, headers: auth(read_write)
      end

      it "creates the bookmark" do
        expect(response).to have_http_status(:created)
      end

      it "accepts tags as an array" do
        expect(Bookmark.last.tags).to contain_exactly("alpha", "beta")
      end

      it "attributes it to the single user" do
        expect(Bookmark.last.user).to eq(user)
      end
    end

    it "rejects a read-only key" do
      post "/bookmarks.json", params: payload.to_json, headers: auth(read_only)

      expect(response).to have_http_status(:forbidden)
    end

    it "wraps validation errors in an errors key, like notes do" do
      Bookmark.create!(url: payload[:bookmark][:url], title: "already here", user: user)

      post "/bookmarks.json", params: payload.to_json, headers: auth(read_write)

      expect(response.parsed_body).to have_key("errors")
    end

    it "rejects a caller with no key" do
      post "/bookmarks.json", params: payload.to_json, headers: {"Content-Type" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /bookmarks/:id.json" do
    let(:bookmark) { Bookmark.create!(url: "https://example.com/e", title: "Before", user: user) }

    it "updates it with a write key" do
      patch "/bookmarks/#{bookmark.id}.json",
        params: {bookmark: {title: "After"}}.to_json, headers: auth(read_write)

      expect(bookmark.reload.title).to eq("After")
    end

    it "rejects a read-only key" do
      patch "/bookmarks/#{bookmark.id}.json",
        params: {bookmark: {title: "After"}}.to_json, headers: auth(read_only)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /notes.json" do
    let(:payload) { {note: {string_data: "a new note", tags: ["gamma"], private: true}} }

    context "with a write key" do
      before { post "/notes.json", params: payload.to_json, headers: auth(read_write) }

      it "creates the note" do
        expect(response).to have_http_status(:created)
      end

      it "returns the created note" do
        expect(response.parsed_body["string_data"]).to eq("a new note")
      end

      it "accepts tags as an array" do
        expect(Note.last.tags).to contain_exactly("gamma")
      end
    end

    it "reports validation errors as json" do
      post "/notes.json", params: {note: {string_data: ""}}.to_json, headers: auth(read_write)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "wraps validation errors in an errors key" do
      post "/notes.json", params: {note: {string_data: ""}}.to_json, headers: auth(read_write)

      expect(response.parsed_body).to have_key("errors")
    end

    it "rejects a read-only key" do
      post "/notes.json", params: payload.to_json, headers: auth(read_only)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /notes/:id.json" do
    let(:note) { Note.create!(string_data: "before", private: false) }

    it "updates it with a write key" do
      patch "/notes/#{note.id}.json",
        params: {note: {string_data: "after"}}.to_json, headers: auth(read_write)

      expect(note.reload.string_data).to eq("after")
    end

    it "rejects a read-only key" do
      patch "/notes/#{note.id}.json",
        params: {note: {string_data: "after"}}.to_json, headers: auth(read_only)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
