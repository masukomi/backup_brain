require "rails_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles, RSpec/AnyInstance
RSpec.describe FetchMisskeyBookmarksJob do
  let(:job) { described_class.new }
  let(:base_url) { "https://misskey.example.com" }
  let(:access_token) { "test_token_abc" }

  let(:misskey_type) do
    OauthSiteType.create!(
      name: "Misskey",
      slug: "misskey",
      registration_strategy: "indie_auth",
      authorization_path: "/oauth/authorize",
      token_path: "/oauth/token",
      default_scopes: ["read:favorites"],
      requires_pkce: true
    )
  end

  let(:oauth_site) do
    OauthSite.create!(
      base_url: base_url,
      registered_url: "https://brain.example.com",
      oauth_site_type: misskey_type,
      client_id: "https://brain.example.com",
      client_secret: nil,
      client_secret_expires_at: 0,
      access_token: access_token
    )
  end

  let(:user) { User.first || create(:user) }

  def build_note(id: "note1", text: "Hello from Misskey", url: nil, username: "alice", host: nil, created_at: "2024-01-15T10:30:00.000Z", files: [])
    {
      "id" => id,
      "text" => text,
      "url" => url,
      "createdAt" => created_at,
      "user" => {
        "id" => "user1",
        "username" => username,
        "host" => host,
        "name" => "Alice",
        "avatarUrl" => "https://misskey.example.com/avatar.jpg",
        "bannerUrl" => nil
      },
      "files" => files
    }
  end

  def build_favorite(id: "fav1", note: nil)
    note ||= build_note
    {"id" => id, "note" => note}
  end

  def stub_favorites_page(favorites, base = base_url)
    response = double("HTTParty::Response", success?: true, body: favorites.to_json)
    allow(HTTParty).to receive(:post).with(
      "#{base}/api/i/favorites",
      anything
    ).and_return(response)
  end

  def stub_empty_favorites(base = base_url)
    response = double("HTTParty::Response", success?: true, body: [].to_json)
    allow(HTTParty).to receive(:post).with("#{base}/api/i/favorites", anything).and_return(response)
  end

  def stub_meilisearch(bookmark)
    allow(bookmark).to receive(:add_to_search)
    allow(bookmark).to receive(:update_in_search)
    allow(bookmark).to receive(:remove_from_search)
  end

  before do
    # Stub Meilisearch callbacks on all Bookmark instances
    allow_any_instance_of(Bookmark).to receive(:add_to_search)
    allow_any_instance_of(Bookmark).to receive(:update_in_search)
    allow_any_instance_of(Bookmark).to receive(:remove_from_search)
    # Stub SMA archiving to avoid real HTTP
    allow(ArchiveSocialMediaAccountJob).to receive(:perform_later)
    # Suppress logger noise
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  after do
    Bookmark.destroy_all
    Tag.destroy_all
    OauthSite.destroy_all
    OauthSiteType.destroy_all
  end

  describe "#manual_perform" do
    context "when no Misskey OauthSiteType exists" do
      it "logs a warning and returns without error" do
        expect(Rails.logger).to receive(:warn).with(/no misskey OauthSiteType/)
        job.manual_perform(false)
      end

      it "returns true" do
        expect(job.manual_perform(false)).to be(true)
      end
    end

    context "when access_token is blank on an OauthSite" do
      before do
        misskey_type
        OauthSite.create!(
          base_url: base_url,
          registered_url: "https://brain.example.com",
          oauth_site_type: misskey_type,
          client_id: "https://brain.example.com",
          client_secret: nil,
          client_secret_expires_at: 0,
          access_token: nil
        )
        user
      end

      it "skips that site and makes no HTTP calls" do
        expect(HTTParty).not_to receive(:post)
        job.manual_perform(false)
      end
    end

    context "with a note that has text content" do
      before do
        misskey_type
        oauth_site
        user
        stub_favorites_page([build_favorite])
        # Second call (cursor pagination) returns empty
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite].to_json),
          double("HTTParty::Response", success?: true, body: [].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
      end

      it "creates a Bookmark with the misskey_bookmark tag" do
        job.manual_perform(false)
        expect(Bookmark.where(tags: "misskey_bookmark").count).to eq(1)
      end

      it "sets the bookmark description from note text" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.description).to include("Hello from Misskey")
      end

      it "includes a formatted timestamp in the title" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.title).to include("2024/01/15 10:30")
      end
    end

    context "with a local note (no url field)" do
      before do
        misskey_type
        oauth_site
        user
        note = build_note(id: "abc123", url: nil)
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite(note: note)].to_json),
          double("HTTParty::Response", success?: true, body: [].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
      end

      it "constructs the URL as {base_url}/notes/{id}" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.url).to eq("#{base_url}/notes/abc123")
      end
    end

    context "with a remote note (has url field)" do
      let(:remote_url) { "https://other.instance.example.com/notes/xyz999" }

      before do
        misskey_type
        oauth_site
        user
        note = build_note(id: "xyz999", url: remote_url)
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite(note: note)].to_json),
          double("HTTParty::Response", success?: true, body: [].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
      end

      it "uses the url field directly" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.url).to eq(remote_url)
      end
    end

    context "when a note URL already exists as a Bookmark" do
      before do
        misskey_type
        oauth_site
        user
        existing_url = "#{base_url}/notes/note1"
        Bookmark.create!(url: existing_url, title: "existing", user: user)
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
      end

      after { Tag.destroy_all }

      it "does not create a duplicate bookmark" do
        expect { job.manual_perform(false) }.not_to change(Bookmark, :count)
      end
    end

    context "with a note that has Image files" do
      let(:image_file) do
        {
          "type" => "Image",
          "url" => "https://misskey.example.com/files/photo.jpg",
          "thumbnailUrl" => "https://misskey.example.com/files/photo_thumb.jpg",
          "comment" => "A photo"
        }
      end

      before do
        misskey_type
        oauth_site
        user
        note = build_note(files: [image_file])
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite(note: note)].to_json),
          double("HTTParty::Response", success?: true, body: [].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset)
          .with(anything, image_file["url"], asset_label: "misskey_media")
          .and_return("/archives/bookmarks/123/photo.jpg")
      end

      it "includes an image line in the archive" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.archives.first.string_data).to include("![")
      end
    end

    context "with a note that has no text but has image files" do
      let(:image_file) do
        {
          "type" => "Image",
          "url" => "https://misskey.example.com/files/photo.jpg",
          "thumbnailUrl" => nil,
          "comment" => nil
        }
      end

      before do
        misskey_type
        oauth_site
        user
        note = build_note(text: nil, files: [image_file])
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything).and_return(
          double("HTTParty::Response", success?: true, body: [build_favorite(note: note)].to_json),
          double("HTTParty::Response", success?: true, body: [].to_json)
        )
        allow_any_instance_of(described_class).to receive(:download_asset)
          .and_return("/archives/bookmarks/123/photo.jpg")
      end

      it "still creates a bookmark" do
        job.manual_perform(false)
        expect(Bookmark.where(tags: "misskey_bookmark").count).to eq(1)
      end

      it "creates an archive containing the image line" do
        job.manual_perform(false)
        bookmark = Bookmark.where(tags: "misskey_bookmark").first
        expect(bookmark.archives.first.string_data).to include("![")
      end
    end

    context "when paginating" do
      let(:first_favorite) { build_favorite(id: "fav1", note: build_note(id: "note1")) }
      let(:second_favorite) { build_favorite(id: "fav2", note: build_note(id: "note2", text: "second note")) }

      before do
        misskey_type
        oauth_site
        user
        # First call (no cursor) returns first_favorite
        # Second call (with untilId: fav1) returns second_favorite
        # Third call (with untilId: fav2) returns empty
        call_count = 0
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything) do
          call_count += 1
          body = case call_count
          when 1 then [first_favorite].to_json
          when 2 then [second_favorite].to_json
          else [].to_json
          end
          double("HTTParty::Response", success?: true, body: body)
        end
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
      end

      it "stops when a page returns empty" do
        job.manual_perform(false)
        expect(Bookmark.where(tags: "misskey_bookmark").count).to eq(2)
      end

      it "passes untilId from the last favorite's id on subsequent pages" do # rubocop:disable RSpec/ExampleLength
        bodies_sent = []
        call_count = 0
        allow(HTTParty).to receive(:post).with("#{base_url}/api/i/favorites", anything) do |_url, opts|
          bodies_sent << JSON.parse(opts[:body])
          call_count += 1
          body = case call_count
          when 1 then [first_favorite].to_json
          when 2 then [second_favorite].to_json
          else [].to_json
          end
          double("HTTParty::Response", success?: true, body: body)
        end
        allow_any_instance_of(described_class).to receive(:download_asset).and_return(nil)
        job.manual_perform(false)
        expect(bodies_sent.any? { |b| b["untilId"] == "fav1" }).to be(true)
      end
    end
  end

  describe "#build_title" do
    let(:note) do
      build_note(
        created_at: "2024-03-20T14:05:00.000Z",
        username: "bob"
      ).merge("user" => {"username" => "bob", "host" => nil, "name" => "Bob Smith"})
    end

    it "includes the display name when present" do
      title = job.send(:build_title, note)
      expect(title).to include("Bob Smith")
    end

    it "falls back to @username when name is blank" do
      note["user"]["name"] = ""
      title = job.send(:build_title, note)
      expect(title).to include("@bob")
    end

    it "includes a formatted timestamp" do
      title = job.send(:build_title, note)
      expect(title).to include("2024/03/20 14:05")
    end
  end

  describe "#note_url" do
    it "returns the note's url field when present" do
      note = {"id" => "abc", "url" => "https://other.com/notes/abc"}
      expect(job.send(:note_url, note, base_url)).to eq("https://other.com/notes/abc")
    end

    it "constructs a local URL when url is nil" do
      note = {"id" => "abc123", "url" => nil}
      expect(job.send(:note_url, note, base_url)).to eq("#{base_url}/notes/abc123")
    end

    it "constructs a local URL when url is empty string" do
      note = {"id" => "xyz", "url" => ""}
      expect(job.send(:note_url, note, base_url)).to eq("#{base_url}/notes/xyz")
    end
  end

  describe "#profile_url_for" do
    it "returns base_url/@username for local users" do
      user_data = {"username" => "alice", "host" => nil}
      expect(job.send(:profile_url_for, user_data, base_url)).to eq("#{base_url}/@alice")
    end

    it "returns https://host/@username for remote users" do
      user_data = {"username" => "alice", "host" => "remote.example.com"}
      expect(job.send(:profile_url_for, user_data, base_url)).to eq("https://remote.example.com/@alice")
    end

    it "returns nil when username is blank" do
      user_data = {"username" => "", "host" => nil}
      expect(job.send(:profile_url_for, user_data, base_url)).to be_nil
    end
  end

  describe "#truncate_text" do
    it "returns text unchanged when at or under the limit" do
      text = "short text"
      expect(job.send(:truncate_text, text, 100)).to eq(text)
    end

    it "truncates after the limit at the next word boundary" do
      text = ("a" * 10) + " extra words here"
      result = job.send(:truncate_text, text, 10)
      expect(result).to eq("a" * 10)
    end

    it "does not cut in the middle of a word" do
      text = "hello worldfoo"
      result = job.send(:truncate_text, text, 8)
      # limit of 8 lands in the middle of "worldfoo" — no whitespace to break at,
      # so we advance to end of string
      expect(result).to eq("hello worldfoo")
    end
  end

  describe "#embed_youtube_videos" do
    let(:archive) { Archive.new(mime_type: "text/markdown", string_data: content) }

    context "when the archive contains a youtube.com/watch URL" do
      let(:content) { "check https://www.youtube.com/watch?v=dQw4w9WgXcQ" }

      it "appends an iframe embed" do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to include("<iframe")
      end
    end

    context "when there are no YouTube URLs" do
      let(:content) { "just some plain text" }

      it "does not modify the archive" do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to eq(content)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles, RSpec/AnyInstance
