require "rails_helper"

RSpec.describe Bookmark do
  let(:old_archive) { Archive.new(string_data: "old_archive_text", created_at: 2.days.ago) }
  let(:new_archive) { Archive.new(string_data: "new_archive_text", created_at: 1.day.ago) }
  let(:bookmark) { described_class.new(archives: [old_archive, new_archive]) }
  let(:empty_archives_bookmark) { described_class.new(archives: []) }
  let(:nil_archives_bookmark) { described_class.new(archives: nil) }

  describe "#archives_text" do
    it "returns nil if there are no archives", :aggregate_failures do
      expect(empty_archives_bookmark.archives_text).to(be_nil)
      expect(nil_archives_bookmark.archives_text).to(be_nil)
    end

    it "returns the text of the latest archive" do
      expect(bookmark.archives_text).to(include("new_archive_text"))
    end

    it "does not include the text of any other archives" do
      expect(bookmark.archives_text).not_to(include("old_archive_text"))
    end
  end

  describe "replace_tag!" do
    let(:bookmark) {
      described_class.new(
        title: "example",
        url: "https://example.com?replace_tag_test=true",
        tags: %w[foo bar baz]
      )
    }

    describe "class method" do
      before do
        allow(described_class).to(receive(:tagged_with).with(anything).and_return([bookmark]))
      end

      it "replaces tags in bookmarks" do
        expect(bookmark).to(receive(:replace_tag!).with("bar", "yay"))
        described_class.replace_tag!("bar", "yay")
      end
    end

    # rubocop:disable RSpec/StubbedMock
    describe "instance method" do
      it "replaces the tag", :aggregate_failures do
        expect(bookmark).to(receive(:save!).and_return(true))
        new_tags = bookmark.replace_tag!("bar", "yay")
        expect(new_tags.include?("yay")).to(be(true))
        expect(new_tags.include?("bar")).to(be(false))
      end
    end
    # rubocop:enable RSpec/StubbedMock
  end
end
