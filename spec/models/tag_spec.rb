require "rails_helper"

RSpec.describe Tag do
  describe ".split_tags" do
    it "returns empty array for blank string" do
      expect(described_class.split_tags(" ")).to(eq([]))
    end

    it "splits comma only separated things" do
      expect(described_class.split_tags("foo,bar,baz")).to(eq(%w[foo bar baz]))
    end

    it "splits comma & space separated things" do
      expect(described_class.split_tags("foo, bar, baz")).to(eq(%w[foo bar baz]))
    end

    it "splits space separated things" do
      expect(described_class.split_tags("foo bar baz")).to(eq(%w[foo bar baz]))
    end

    it "does not include blank entries" do
      expect(described_class.split_tags("foo,,bar  baz")).to(eq(%w[foo bar baz]))
    end

    it "does not include duplicate entries" do
      expect(described_class.split_tags("foo bar, foo")).to(eq(%w[foo bar]))
    end

    it "downcases entries" do
      expect(described_class.split_tags("FOO Bar, bAz")).to(eq(%w[foo bar baz]))
    end
  end

  describe "valid_tags" do
    # tags are valid if they're
    # - not blank
    # - contain no whitespace (\t, \s, \n, \r, etc)
    # - have no upper case letters
    it "returns all valid tags" do
      expect(described_class.valid_tags(%w[foo bar baz])).to(eq(%w[foo bar baz]))
    end

    it "returns no invalid tags" do
      expect(described_class.valid_tags(
        [
          "Foo",
          "bar",
          "bAz",
          "",
          "     ",
          " foo ",
          "foo ",
          "  foo"
        ]
      )).to(eq(["bar"]))
    end
  end

  describe "single_tag_only" do
    it "lets a valid tag be valid" do
      expect(described_class.new(name: "foo").valid?).to(be(true))
    end

    it "marks a multi-word tag as invalid" do
      # under the covers this uses split_tags which we've tested
      # all the variations of above.
      expect(described_class.new(name: "foo bad").valid?).to(be(false))
    end
  end

  describe ".orphaned_tag_names" do
    let(:user) { User.first || create(:user) }

    # rubocop:disable RSpec/AnyInstance
    before do
      allow_any_instance_of(Bookmark).to receive(:add_to_search)
      allow_any_instance_of(Bookmark).to receive(:update_in_search)
      allow_any_instance_of(Bookmark).to receive(:remove_from_search)
      described_class.destroy_all
      Bookmark.destroy_all
    end
    # rubocop:enable RSpec/AnyInstance

    after do
      described_class.destroy_all
      Bookmark.destroy_all
    end

    it "returns empty array when there are no tags" do
      expect(described_class.orphaned_tag_names).to(be_empty)
    end

    it "returns all tag names when no bookmarks exist" do
      described_class.create!(name: "orphan1")
      described_class.create!(name: "orphan2")
      expect(described_class.orphaned_tag_names).to(match_array(%w[orphan1 orphan2]))
    end

    it "does not return tag names that are used in a bookmark" do
      # after_save auto-creates the Tag for "used" via update_central_tags_list
      Bookmark.create!(title: "b", url: "https://example.com/orphan-test-used", tags: ["used"], user: user)
      expect(described_class.orphaned_tag_names).to(be_empty)
    end

    it "returns only unused tags when some tags are used and some are not" do
      Bookmark.create!(title: "b", url: "https://example.com/orphan-test-mixed", tags: ["used"], user: user)
      # Insert orphan directly to bypass the ensure_no_orphans! callback triggered by Bookmark#after_save
      described_class.collection.insert_one({name: "orphan"})
      expect(described_class.orphaned_tag_names).to(eq(["orphan"]))
    end

    it "handles a bookmark whose tags are spread across multiple bookmarks" do
      Bookmark.create!(title: "b1", url: "https://example.com/orphan-test-multi-1", tags: ["foo"], user: user)
      Bookmark.create!(title: "b2", url: "https://example.com/orphan-test-multi-2", tags: ["bar"], user: user)
      described_class.collection.insert_one({name: "orphan"})
      expect(described_class.orphaned_tag_names).to(eq(["orphan"]))
    end
  end

  describe "multi-insert" do
    let(:temp_names) { %w[ex1 ex2 ex3] }

    after do
      described_class.where(name: {"$in" => temp_names}).destroy_all
    end

    describe ".create_many_by_name_if_needeed" do
      it "onlies create needed ones" do
        described_class.create(name: temp_names.first)
        expect {
          described_class.create_many_by_name_if_needed(temp_names)
        }.to change(described_class, :count).by(2)
      end
    end

    describe ".create_many_by_name" do
      it "creates many" do
        expect {
          described_class.create_many_by_name(temp_names)
        }.to change(described_class, :count).by(3)
      end
    end
  end
end
