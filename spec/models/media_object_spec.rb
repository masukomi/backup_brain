require "rails_helper"

RSpec.describe MediaObject do
  let(:user) { User.first || create(:user) }

  def new_bookmark(url_suffix)
    b = Bookmark.new(
      title: "cascade test",
      url: "https://example.com/cascade_#{url_suffix}",
      user: user
    )
    allow(b).to receive(:add_to_search)
    allow(b).to receive(:update_in_search)
    allow(b).to receive(:remove_from_search)
    b
  end

  after do
    Bookmark.destroy_all
    Tag.destroy_all
  end

  describe "cascade_callbacks" do
    # MediaObject is embedded in Archive which is embedded in Bookmark.
    # Mongoid does not propagate after_create callbacks beyond one level of
    # nesting by default. Both embeds_many declarations must use
    # cascade_callbacks: true to ensure after_create :transcribe fires when
    # the root Bookmark is saved — regardless of whether the MediaObject is
    # being added to a brand-new bookmark or an existing one.

    context "when a MediaObject is added to an archive on a new, unsaved Bookmark" do
      it "calls transcribe when the Bookmark is first saved" do
        bookmark = new_bookmark("new")
        archive = bookmark.archives.build(string_data: "content", mime_type: "text/markdown")
        mo = archive.media_objects.build(url: "https://example.com/audio.mp3", simple_type: "audio")

        expect(mo).to receive(:transcribe)
        bookmark.save!
      end
    end

    context "when a MediaObject is added to an archive on an already-persisted Bookmark" do
      it "calls transcribe when the Bookmark is saved again" do
        bookmark = new_bookmark("existing")
        bookmark.archives.build(string_data: "content", mime_type: "text/markdown")
        bookmark.save!

        archive = bookmark.archives.last
        mo = archive.media_objects.build(url: "https://example.com/audio.mp3", simple_type: "audio")

        expect(mo).to receive(:transcribe)
        bookmark.save!
      end
    end
  end

  describe "#web_path" do
    before do
      allow(Setting).to receive(:get_value_of_key) { |key, **| {"s3_bucket" => "bb-archives"}[key] }
    end

    it "returns local archive paths unchanged" do
      mo = described_class.new(url: "/archives/bookmarks/abc/f.mp3", simple_type: "audio")
      expect(mo.web_path).to eq("/archives/bookmarks/abc/f.mp3")
    end

    it "returns remote http urls unchanged" do
      mo = described_class.new(url: "https://example.com/f.mp3", simple_type: "audio")
      expect(mo.web_path).to eq("https://example.com/f.mp3")
    end

    it "maps s3 urls to the archive path ArchivesController serves" do
      mo = described_class.new(url: "s3://bb-archives/bookmarks/abc/f.mp3", simple_type: "audio")
      expect(mo.web_path).to eq("/archives/bookmarks/abc/f.mp3")
    end
  end

  describe "#stored_in_s3?" do
    it "is true for s3 urls" do
      expect(described_class.new(url: "s3://bb-archives/x.mp3", simple_type: "audio").stored_in_s3?).to be(true)
    end

    it "is false for local paths" do
      expect(described_class.new(url: "/archives/bookmarks/abc/f.mp3", simple_type: "audio").stored_in_s3?).to be(false)
    end
  end
end
