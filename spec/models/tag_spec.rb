require "rails_helper"

RSpec.describe Tag do
  describe ".extract_tags_from_string" do
    it "returns the original string and empty array when there are no hashtags" do
      expect(described_class.extract_tags_from_string("hello world")).to(eq(["hello world", []]))
    end

    it "returns the original string and empty array for an empty string" do
      expect(described_class.extract_tags_from_string("")).to(eq(["", []]))
    end

    it "does not treat a # in the middle of a word as a hashtag" do
      expect(described_class.extract_tags_from_string("abc#notag")).to(eq(["abc#notag", []]))
    end

    it "extracts a single tag at the end of the string" do
      expect(described_class.extract_tags_from_string("my friend #foo")).to(eq(["my friend", ["foo"]]))
    end

    it "extracts a single tag in the middle of the string" do
      expect(described_class.extract_tags_from_string("my #foo friend")).to(eq(["my friend", ["foo"]]))
    end

    it "extracts a tag at the start of the string" do
      expect(described_class.extract_tags_from_string("#foo bar")).to(eq(["bar", ["foo"]]))
    end

    it "extracts multiple tags and returns them in order" do
      expect(described_class.extract_tags_from_string("my friend #foo bar #baz")).to(eq(["my friend bar", ["foo", "baz"]]))
    end

    it "returns an empty string when the input is only a hashtag" do
      expect(described_class.extract_tags_from_string("#foo")).to(eq(["", ["foo"]]))
    end

    it "returns an empty string when the input is only hashtags" do
      expect(described_class.extract_tags_from_string("#c #a #b")).to(eq(["", ["c", "a", "b"]]))
    end

    it "handles tags containing underscores and digits" do
      expect(described_class.extract_tags_from_string("see #foo_bar2")).to(eq(["see", ["foo_bar2"]]))
    end

    it "downcases extracted tags by default" do
      expect(described_class.extract_tags_from_string("my friend #Foo bar #BAZ")).to(eq(["my friend bar", ["foo", "baz"]]))
    end

    it "preserves tag case when downcase: false is passed" do
      expect(described_class.extract_tags_from_string("my friend #Foo bar #BAZ", downcase: false)).to(eq(["my friend bar", ["Foo", "BAZ"]]))
    end

    it "downcases when downcase: true is passed explicitly" do
      expect(described_class.extract_tags_from_string("#MixedCase", downcase: true)).to(eq(["", ["mixedcase"]]))
    end
  end

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
    before do
      described_class.collection.delete_many({})
      Bookmark.collection.delete_many({})
    end

    after do
      described_class.collection.delete_many({})
      Bookmark.collection.delete_many({})
    end

    it "returns empty array when there are no tags" do
      expect(described_class.orphaned_tag_names).to(be_empty)
    end

    it "returns all tag names when no bookmarks exist" do
      described_class.collection.insert_many([{name: "orphan1"}, {name: "orphan2"}])
      expect(described_class.orphaned_tag_names).to(match_array(%w[orphan1 orphan2]))
    end

    it "does not return tag names that are used in a bookmark" do
      described_class.collection.insert_one({name: "used"})
      Bookmark.collection.insert_one({tags: ["used"]})
      expect(described_class.orphaned_tag_names).to(be_empty)
    end

    it "returns only unused tags when some tags are used and some are not" do
      described_class.collection.insert_many([{name: "used"}, {name: "orphan"}])
      Bookmark.collection.insert_one({tags: ["used"]})
      expect(described_class.orphaned_tag_names).to(eq(["orphan"]))
    end

    it "handles tags spread across multiple bookmarks" do
      described_class.collection.insert_many([{name: "foo"}, {name: "bar"}, {name: "orphan"}])
      Bookmark.collection.insert_one({tags: ["foo"]})
      Bookmark.collection.insert_one({tags: ["bar"]})
      expect(described_class.orphaned_tag_names).to(eq(["orphan"]))
    end
  end

  describe ".regenerate_all!" do
    before do
      Bookmark.collection.delete_many({})
      described_class.collection.delete_many({})
    end

    after do
      Bookmark.collection.delete_many({})
      described_class.collection.delete_many({})
    end

    it "creates tags for all tags used in bookmarks", :aggregate_failures do
      Bookmark.collection.insert_one({tags: %w[foo bar]})
      expect { described_class.regenerate_all! }.to change(described_class, :count).by(2)
      expect(described_class.pluck(:name)).to(match_array(%w[foo bar]))
    end

    it "removes tags that are no longer used in any bookmark" do
      described_class.collection.insert_one({name: "stale"})
      expect { described_class.regenerate_all! }.to change(described_class, :count).by(-1)
    end

    it "keeps tags that are still used and creates missing ones" do
      described_class.collection.insert_one({name: "existing"})
      Bookmark.collection.insert_one({tags: %w[existing new_tag]})
      described_class.regenerate_all!
      expect(described_class.pluck(:name)).to(match_array(%w[existing new_tag]))
    end

    it "raises on invalid tag names found in bookmarks" do
      Bookmark.collection.insert_one({tags: ["Invalid Tag"]})
      expect { described_class.regenerate_all! }.to(raise_error(BackupBrain::Errors::InvalidTag))
    end

    it "returns true on success" do
      expect(described_class.regenerate_all!).to(be(true))
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
