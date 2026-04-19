require "rails_helper"

RSpec.describe ContentTrigger do
  after do
    described_class.destroy_all
  end

  describe "validations" do
    it "is valid with a name and simple_triggers" do
      trigger = described_class.new(name: "My Trigger", simple_triggers: ["foo"])
      expect(trigger).to be_valid
    end

    it "is invalid without a name" do
      trigger = described_class.new(name: nil)
      expect(trigger).not_to be_valid
    end

    it "sets a name error when name is blank" do
      trigger = described_class.new(name: nil)
      trigger.valid?
      expect(trigger.errors[:name]).to be_present
    end

    it "is invalid with a duplicate name" do
      described_class.create!(name: "Dupe Trigger")
      trigger = described_class.new(name: "Dupe Trigger")
      expect(trigger).not_to be_valid
    end

    it "sets a name error on duplicate name" do
      described_class.create!(name: "Dupe Trigger")
      trigger = described_class.new(name: "Dupe Trigger")
      trigger.valid?
      expect(trigger.errors[:name]).to be_present
    end

    it "defaults case_insensitive to true" do
      trigger = described_class.new(name: "x")
      expect(trigger.case_insensitive).to be true
    end

    it "defaults mark_as_private to false" do
      trigger = described_class.new(name: "x")
      expect(trigger.mark_as_private).to be false
    end

    it "defaults simple_triggers to an empty array" do
      trigger = described_class.new(name: "x")
      expect(trigger.simple_triggers).to eq([])
    end
  end

  describe "#applies?" do
    context "with no simple_triggers" do
      let(:trigger) { described_class.new(name: "t", simple_triggers: []) }

      it "returns false" do
        expect(trigger.applies?("some string data")).to be false
      end
    end

    context "when case_insensitive is true" do
      let(:trigger) do
        described_class.new(name: "t", simple_triggers: ["youtube"], case_insensitive: true)
      end

      it "returns true when the string matches (case-insensitively)" do
        expect(trigger.applies?("Check out this YouTube video")).to be true
      end

      it "returns false when the string does not match" do
        expect(trigger.applies?("Nothing here")).to be false
      end

      it "matches regardless of case" do
        expect(trigger.applies?("YOUTUBE is great")).to be true
      end
    end

    context "when case_insensitive is false" do
      let(:trigger) do
        described_class.new(name: "t", simple_triggers: ["youtube"], case_insensitive: false)
      end

      it "returns true when the string matches exactly" do
        expect(trigger.applies?("watch youtube today")).to be true
      end

      it "returns false when the string matches only by different case" do
        expect(trigger.applies?("watch YouTube today")).to be false
      end
    end
  end

  describe ".cached_triggers" do
    it "returns all ContentTrigger records" do
      trigger = described_class.create!(name: "Cached One", simple_triggers: ["foo"])
      expect(described_class.cached_triggers).to include(trigger)
    end

    it "memoizes the result" do
      described_class.create!(name: "Memoized", simple_triggers: ["bar"])
      first_call = described_class.cached_triggers
      second_call = described_class.cached_triggers
      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe "cache busting" do
    it "warms the cache before save" do
      described_class.cached_triggers
      expect(described_class.instance_variable_get(:@cached_triggers)).not_to be_nil
    end

    it "clears @cached_triggers after save" do
      described_class.cached_triggers
      described_class.create!(name: "Bust Me", simple_triggers: ["baz"])
      expect(described_class.instance_variable_get(:@cached_triggers)).to be_nil
    end
  end

  describe ".apply_triggers" do
    context "with an unsupported document type" do
      it "raises UnsupportedDocumentType" do
        expect {
          described_class.apply_triggers(Setting.new)
        }.to raise_error(BackupBrain::Errors::UnsupportedDocumentType)
      end
    end

    context "with a supported document type" do
      # BUG: apply_triggers calls self.cached_values (undefined) instead of
      # self.cached_triggers. This raises NoMethodError at runtime.
      # This test documents the current broken behavior so it fails when the
      # bug is fixed, prompting updated expectations.
      it "raises NoMethodError due to cached_values bug" do
        described_class.create!(name: "YT Trigger", simple_triggers: ["youtube"])
        bookmark = Bookmark.new(title: "youtube video", url: "https://youtube.com/watch?v=xyz")
        expect {
          described_class.apply_triggers(bookmark)
        }.to raise_error(NoMethodError)
      end
    end
  end

  describe "#apply_to" do
    let(:trigger) do
      described_class.new(
        name: "t",
        simple_triggers: ["foo"],
        mark_as_private: true,
        tags: ["autotag"]
      )
    end

    it "applies mark_as_private to the document" do
      bookmark = Bookmark.new(title: "foo bar", url: "https://example.com", tags: [], private: false)
      trigger.apply_to(bookmark)
      expect(bookmark.private).to be true
    end

    it "merges trigger tags onto the document" do
      bookmark = Bookmark.new(title: "foo bar", url: "https://example.com", tags: [], private: false)
      trigger.apply_to(bookmark)
      expect(bookmark.tags).to include("autotag")
    end
  end
end
