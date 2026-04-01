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
end
