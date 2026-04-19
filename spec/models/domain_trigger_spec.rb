require "rails_helper"

RSpec.describe DomainTrigger do
  after do
    described_class.destroy_all
  end

  describe "validations" do
    it "is valid with a domain" do
      trigger = described_class.new(domain: "example.com")
      expect(trigger).to be_valid
    end

    it "is invalid without a domain" do
      trigger = described_class.new(domain: nil)
      expect(trigger).not_to be_valid
    end

    it "sets a domain error when domain is blank" do
      trigger = described_class.new(domain: nil)
      trigger.valid?
      expect(trigger.errors[:domain]).to be_present
    end

    it "is invalid with a duplicate domain" do
      described_class.create!(domain: "example.com")
      trigger = described_class.new(domain: "example.com")
      expect(trigger).not_to be_valid
    end

    it "sets a domain error on duplicate domain" do
      described_class.create!(domain: "example.com")
      trigger = described_class.new(domain: "example.com")
      trigger.valid?
      expect(trigger.errors[:domain]).to be_present
    end

    it "is invalid with a malformed domain" do
      trigger = described_class.new(domain: "not a domain")
      expect(trigger).not_to be_valid
    end

    it "defaults mark_as_private to false" do
      trigger = described_class.new(domain: "example.com")
      expect(trigger.mark_as_private).to be false
    end

    it "defaults mark_as_sensitive to false" do
      trigger = described_class.new(domain: "example.com")
      expect(trigger.mark_as_sensitive).to be false
    end

    it "defaults mark_to_read to false" do
      trigger = described_class.new(domain: "example.com")
      expect(trigger.mark_to_read).to be false
    end
  end

  describe ".trigger_for_domain" do
    it "returns the trigger matching the domain" do
      trigger = described_class.create!(domain: "example.com")
      expect(described_class.trigger_for_domain("example.com")).to eq(trigger)
    end

    it "returns nil for an unknown domain" do
      expect(described_class.trigger_for_domain("unknown.com")).to be_nil
    end
  end

  describe ".cached_values" do
    it "returns a hash of triggers indexed by domain" do
      trigger = described_class.create!(domain: "example.com")
      expect(described_class.cached_values["example.com"]).to eq(trigger)
    end

    it "memoizes the result" do
      described_class.create!(domain: "example.com")
      first_call = described_class.cached_values
      second_call = described_class.cached_values
      expect(first_call.object_id).to eq(second_call.object_id)
    end
  end

  describe "cache busting" do
    it "warms the cache before save" do
      described_class.cached_values
      expect(described_class.instance_variable_get(:@cached_values)).not_to be_nil
    end

    it "clears @cached_values after save" do
      described_class.cached_values
      described_class.create!(domain: "example.com")
      expect(described_class.instance_variable_get(:@cached_values)).to be_nil
    end
  end

  describe "#apply_to" do
    let(:trigger) do
      described_class.new(
        domain: "example.com",
        mark_as_sensitive: true,
        tags: ["sensitive-tag"]
      )
    end

    it "applies mark_as_sensitive to the document" do
      bookmark = Bookmark.new(title: "Test", url: "https://example.com", tags: [], sensitive: false)
      trigger.apply_to(bookmark)
      expect(bookmark.sensitive).to be true
    end

    it "merges trigger tags onto the document" do
      bookmark = Bookmark.new(title: "Test", url: "https://example.com", tags: [])
      trigger.apply_to(bookmark)
      expect(bookmark.tags).to include("sensitive-tag")
    end
  end
end
