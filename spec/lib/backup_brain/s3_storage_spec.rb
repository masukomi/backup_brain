require "rails_helper"

RSpec.describe BackupBrain::S3Storage do
  let(:settings) do
    {
      "enable_s3_storage" => true,
      "s3_endpoint" => "http://localhost:9000",
      "s3_region" => "us-east-1",
      "s3_bucket" => "bb-archives",
      "s3_access_key_id" => "key-id",
      "s3_secret_access_key" => "key-secret",
      "s3_key_prefix" => "",
      "s3_force_path_style" => true,
      "s3_presigned_url_expiry" => 600
    }
  end
  let(:storage) { described_class.new }
  let(:stub_client) do
    Aws::S3::Client.new(stub_responses: true, region: "us-east-1",
      endpoint: "http://localhost:9000", force_path_style: true)
  end

  before do
    allow(Setting).to receive(:get_value_of_key) { |key, **| settings[key] }
    allow(storage).to receive(:client).and_return(stub_client)
  end

  describe ".enabled?" do
    it "is true when the flag is on and credentials are present" do
      expect(described_class.enabled?).to be(true)
    end

    it "is false when the flag is off" do
      settings["enable_s3_storage"] = false
      expect(described_class.enabled?).to be(false)
    end

    it "is false when a credential is blank" do
      settings["s3_secret_access_key"] = " "
      expect(described_class.enabled?).to be(false)
    end

    it "is false when the settings don't exist yet" do
      allow(Setting).to receive(:get_value_of_key).and_return(nil)
      expect(described_class.enabled?).to be(false)
    end
  end

  describe "key and url conversions" do
    it "maps a relative local path to a key" do
      expect(storage.key_for_local_path("archives/bookmarks/abc123/deadbeef.mp3"))
        .to eq("bookmarks/abc123/deadbeef.mp3")
    end

    it "maps an absolute local path to a key" do
      expect(storage.key_for_local_path(Rails.root.join("archives/people/p1/avatar.png").to_s))
        .to eq("people/p1/avatar.png")
    end

    it "maps a web path to a key" do
      expect(storage.key_for_web_path("/archives/bookmarks/abc123/deadbeef.mp3"))
        .to eq("bookmarks/abc123/deadbeef.mp3")
    end

    it "builds an s3 url for a web path" do
      expect(storage.s3_url_for_web_path("/archives/bookmarks/abc123/deadbeef.mp3"))
        .to eq("s3://bb-archives/bookmarks/abc123/deadbeef.mp3")
    end

    it "turns an s3 url back into a web path" do
      expect(storage.web_path_for_s3_url("s3://bb-archives/bookmarks/abc123/deadbeef.mp3"))
        .to eq("/archives/bookmarks/abc123/deadbeef.mp3")
    end

    it "refuses s3 urls for another bucket" do
      expect(storage.key_for_s3_url("s3://someone-else/bookmarks/abc123/deadbeef.mp3")).to be_nil
    end

    it "recognises s3 urls" do
      expect(described_class.s3_url?("s3://bb-archives/x")).to be(true)
    end

    it "does not mistake http urls for s3 urls" do
      expect(described_class.s3_url?("https://example.com/x.mp3")).to be(false)
    end

    context "with a key prefix" do
      before { settings["s3_key_prefix"] = "/backup_brain" }

      it "normalises the prefix to end with a slash" do
        expect(storage.key_prefix).to eq("backup_brain/")
      end

      it "prepends the prefix to keys" do
        expect(storage.key_for_web_path("/archives/bookmarks/abc/f.mp3"))
          .to eq("backup_brain/bookmarks/abc/f.mp3")
      end

      it "strips the prefix when building web paths" do
        expect(storage.web_path_for_key("backup_brain/bookmarks/abc/f.mp3"))
          .to eq("/archives/bookmarks/abc/f.mp3")
      end
    end
  end

  describe "#exists?" do
    it "is true when HEAD succeeds" do
      stub_client.stub_responses(:head_object, {content_length: 12})
      expect(storage.exists?("bookmarks/abc/f.mp3")).to be(true)
    end

    it "is false when the object is missing" do
      stub_client.stub_responses(:head_object, "NotFound")
      expect(storage.exists?("bookmarks/abc/f.mp3")).to be(false)
    end
  end

  describe "#presigned_url" do
    let(:url) { storage.presigned_url("bookmarks/abc/f.mp3") }

    it "points at the configured endpoint and bucket" do
      expect(url).to start_with("http://localhost:9000/bb-archives/bookmarks/abc/f.mp3?")
    end

    it "is signed" do
      expect(url).to include("X-Amz-Signature=")
    end

    it "uses the configured expiry" do
      expect(url).to include("X-Amz-Expires=600")
    end
  end

  describe "#expiry" do
    it "falls back to the default when the setting is missing" do
      settings.delete("s3_presigned_url_expiry")
      expect(storage.expiry).to eq(described_class::DEFAULT_EXPIRY)
    end
  end
end
