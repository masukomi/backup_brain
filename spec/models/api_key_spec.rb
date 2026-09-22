require "rails_helper"

RSpec.describe ApiKey, type: :model do
  after { described_class.destroy_all }

  describe "#generate_key" do
    it "generates a key on create" do
      key = create(:api_key)
      expect(key.key).to match(/\A[0-9a-f]{64}\z/)
    end
  end

  describe ".authenticate" do
    it "returns the record for a valid key" do
      key = create(:api_key)
      expect(described_class.authenticate(key.key)).to eq(key)
    end

    it "returns nil for an unknown key" do
      create(:api_key)
      expect(described_class.authenticate("nope")).to be_nil
    end

    it "returns nil for an empty key" do
      expect(described_class.authenticate("")).to be_nil
    end

    it "returns nil for a nil key" do
      expect(described_class.authenticate(nil)).to be_nil
    end

    it "returns nil for an expired key" do
      key = create(:expired_api_key)
      expect(described_class.authenticate(key.key)).to be_nil
    end

    it "returns the record when the expiration is still in the future" do
      key = create(:api_key, expiration_date: Date.current + 1)
      expect(described_class.authenticate(key.key)).to eq(key)
    end
  end

  describe ".is_valid?" do
    it "is true for a valid key" do
      expect(described_class.is_valid?(create(:api_key).key)).to be true
    end

    it "is false for an expired key" do
      expect(described_class.is_valid?(create(:expired_api_key).key)).to be false
    end
  end

  describe "#permits?" do
    let(:key) { create(:notes_only_api_key) }

    it "is true when the permission is present" do
      expect(key.permits?("read", Note)).to be true
    end

    it "is false for a model the key wasn't granted" do
      expect(key.permits?("read", Bookmark)).to be false
    end

    it "is false for an action the key wasn't granted" do
      expect(key.permits?("write", Note)).to be false
    end

    it "matches the strings AccessHelper generates" do
      helper = Class.new { include AccessHelper }.new
      expect(helper.api_key_permissions_for(Note)).to include("read:notes")
    end
  end

  describe "#expired?" do
    it "is false when there is no expiration date" do
      expect(create(:api_key).expired?).to be false
    end

    it "is false on the expiration date itself" do
      expect(create(:api_key, expiration_date: Date.current).expired?).to be false
    end

    it "is true the day after the expiration date" do
      expect(create(:api_key, expiration_date: Date.current - 1).expired?).to be true
    end
  end
end
