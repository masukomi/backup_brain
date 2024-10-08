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

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "Taggable" do
    let(:bookmark) {
      described_class.new(
        title: "tagged",
        url: "https://example.com?taggable_test=true",
        tags: %w[foo bar baz],
        user: User.first || create(:user)
      )
    }
    let(:untagged) {
      described_class.new(
        title: "untagged",
        url: "https://example.com?taggable=true&untagged=true",
        tags: [],
        user: User.first || create(:user)
      )
    }

    before do
      described_class.destroy_all
    end

    after do
      described_class.destroy_all
    end

    describe "#tagged_with_any" do
      it "does not accept a string input" do
        expect { described_class.tagged_with_any("foo") }.to(raise_error(ArgumentError))
      end

      it "finds things tagged with the full list" do
        bookmark.save!
        expect(described_class.tagged_with_any(%w[foo bar baz]).include?(bookmark)).to(be(true))
      end

      it "does not find things without tags" do
        bookmark.save!
        untagged.save!
        expect(described_class.tagged_with_any(%w[foo bar baz]).include?(untagged)).to(be(false))
      end

      it "finds things tagged with only some of the list" do
        bookmark.save!
        expect(described_class.tagged_with_any(%w[bogus foo bar baz bullshit]).include?(bookmark)).to(be(true))
      end
    end

    describe "#tagged_with_all" do
      it "accepts string input" do
        expect(described_class.tagged_with_all("foo")).to(be_an_instance_of(Mongoid::Criteria))
      end

      it "accepts array input" do
        expect(described_class.tagged_with_all(%w[foo bar])).to(be_an_instance_of(Mongoid::Criteria))
      end

      it "doesn't return bookmarks tagged with only some of an array argument's content" do
        bookmark.save
        expect(described_class.tagged_with_all(%w[foo bullshit]).include?(bookmark)).not_to(be(true))
      end

      it "does return bookmarks tagged with everything in the array" do
        bookmark.save!
        expect(described_class.tagged_with_all(%w[foo bar]).include?(bookmark)).to(be(true))
      end
    end

    describe "replace_tag!" do
      describe "class method" do
        before do
          allow(described_class).to(receive(:tagged_with_all).with(anything).and_return([bookmark]))
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
          expect(bookmark.tags).to(match_array(new_tags))
        end
      end
      # rubocop:enable RSpec/StubbedMock
    end

    describe "remove_tag!" do
      describe "class methods" do
        before do
          allow(described_class).to(receive(:tagged_with_all).with(anything).and_return([bookmark]))
        end

        it "replaces tags in bookmarks" do
          expect(bookmark).to(receive(:remove_tag!).with("bar"))
          described_class.remove_tag!("bar")
        end
      end

      describe "instance method" do
        it "removes the tag" do
          bookmark.remove_tag!("bar")
          expect(bookmark.tags.include?("bar")).to(be(false))
        end
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end
end
