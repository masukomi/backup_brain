require "rails_helper"

RSpec.describe ApiArchiveSource do
  let(:oauth_site) { OauthSite.new(base_url: "https://mastodon.social") }
  let(:bookmark) { Bookmark.new(url: "https://example.com/status/123", title: "Test Bookmark") }

  describe "validations" do
    it "is valid with a remote_id and service" do
      source = described_class.new(remote_id: "12345", service: "mastodon")
      expect(source).to be_valid
    end

    it "is invalid without a remote_id", :aggregate_failures do
      source = described_class.new(service: "mastodon")
      expect(source).not_to be_valid
      expect(source.errors[:remote_id]).to include("can't be blank")
    end

    it "is invalid without a service", :aggregate_failures do
      source = described_class.new(remote_id: "12345")
      expect(source).not_to be_valid
      expect(source.errors[:service]).to include("can't be blank")
    end
  end

  describe "associations" do
    it "can be embedded in a bookmark", :aggregate_failures do
      source = described_class.new(remote_id: "12345", service: "mastodon")
      bookmark.api_archive_source = source
      expect(bookmark.api_archive_source).to eq(source)
      expect(source.bookmark).to eq(bookmark)
    end

    it "can belong to an oauth_site" do
      source = described_class.new(remote_id: "12345", service: "mastodon", oauth_site: oauth_site)
      expect(source.oauth_site).to eq(oauth_site)
    end
  end
end
