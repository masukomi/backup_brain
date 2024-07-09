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
end
