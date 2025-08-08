require "spec_helper"
require "rails_helper"

class FakeModel
  include BackupBrain::ArchiveTools
end

RSpec.describe BackupBrain::ArchiveTools do
  let(:instance) { FakeModel.new }
  let(:bookmark) { Bookmark.new }

  describe "#archive_folder_path_for_doc" do
    let(:path) { instance.archive_folder_path_for_doc(bookmark) }

    it "includes the pluralized class name" do
      expect(path).to(include("bookmarks"))
    end

    it "includes the mongoid id" do
      expect(path).to(include(bookmark._id.to_s))
    end

    it "starts with archives" do
      expect(path.start_with?("archives")).to(be(true))
    end
  end

  describe "#archive_web_path_for_doc" do
    let(:url) { instance.archive_web_path_for_doc(bookmark) }

    it "includes the pluralized class name" do
      expect(url).to(include("bookmarks"))
    end

    it "includes the mongoid id" do
      expect(url).to(include(bookmark._id.to_s))
    end

    it "starts with archives" do
      expect(url.start_with?("/archives/")).to(be(true))
    end
  end
end
