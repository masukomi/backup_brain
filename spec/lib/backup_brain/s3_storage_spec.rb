require "rails_helper"

RSpec.describe BackupBrain::S3Storage do
  # A correctly configured install always has an enabled primary bucket.
  let!(:primary) { create(:s3_bucket, nickname: "main", name: "bb-archives", primary: true) }
  let(:storage) { described_class.new }
  let(:stub_client) do
    Aws::S3::Client.new(stub_responses: true, region: "us-east-1",
      endpoint: "http://localhost:9000", force_path_style: true)
  end

  def add_mirror(enabled: true)
    create(:s3_bucket, nickname: "mirror", name: "bb-backup", key_prefix: "mirror", enabled: enabled)
  end

  before do
    allow(storage).to receive(:client).and_return(stub_client)
  end

  after do
    S3Bucket.destroy_all
    described_class.reload!
  end

  describe ".enabled?" do
    it "is true when an enabled bucket exists" do
      expect(described_class.enabled?).to be(true)
    end

    it "is false when every bucket is disabled" do
      primary.update!(enabled: false, primary: false)
      expect(described_class.enabled?).to be(false)
    end

    it "is false when there are no buckets" do
      S3Bucket.destroy_all
      expect(described_class.enabled?).to be(false)
    end
  end

  describe ".instance" do
    it "defaults to the primary bucket" do
      expect(described_class.instance.bucket).to eq(primary)
    end

    it "is rebuilt when a bucket changes" do
      before_change = described_class.instance
      add_mirror.update!(primary: true)
      expect(described_class.instance).not_to equal(before_change)
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

    it "refuses s3 urls for an unknown bucket" do
      expect(storage.key_for_s3_url("s3://someone-else/bookmarks/abc123/deadbeef.mp3")).to be_nil
    end

    it "refuses s3 urls that don't name the given bucket" do
      mirror = add_mirror
      expect(storage.key_for_s3_url("s3://bb-archives/bookmarks/abc/f.mp3", mirror)).to be_nil
    end

    it "finds the bucket an s3 url points at" do
      mirror = add_mirror
      expect(storage.bucket_for_s3_url("s3://bb-backup/mirror/bookmarks/abc/f.mp3")).to eq(mirror)
    end

    it "turns an s3 url for a known non-primary bucket into a web path" do
      add_mirror
      expect(storage.web_path_for_s3_url("s3://bb-backup/mirror/bookmarks/abc/f.mp3"))
        .to eq("/archives/bookmarks/abc/f.mp3")
    end

    it "builds keys with the given bucket's prefix" do
      mirror = add_mirror
      expect(storage.key_for_web_path("/archives/bookmarks/abc/f.mp3", mirror))
        .to eq("mirror/bookmarks/abc/f.mp3")
    end

    it "recognises s3 urls" do
      expect(described_class.s3_url?("s3://bb-archives/x")).to be(true)
    end

    it "does not mistake http urls for s3 urls" do
      expect(described_class.s3_url?("https://example.com/x.mp3")).to be(false)
    end

    context "with a key prefix" do
      let!(:primary) { create(:s3_bucket, nickname: "main", name: "bb-archives", primary: true, key_prefix: "/backup_brain") }

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

    it "is false without a bucket" do
      expect(storage.exists?("bookmarks/abc/f.mp3", nil)).to be(false)
    end
  end

  describe "#upload_local_file" do
    let(:folder) { Rails.root.join("archives/bookmarks/s3_storage_spec") }
    let(:local_path) { folder.join("f.mp3").to_s }

    before do
      FileUtils.mkdir_p(folder)
      File.write(local_path, "audio bytes")
      stub_client.stub_responses(:head_object, "NotFound")
    end

    after { FileUtils.rm_rf(folder) }

    it "uploads to the primary bucket" do
      expect(stub_client).to receive(:put_object)
        .with(hash_including(bucket: "bb-archives", key: "bookmarks/s3_storage_spec/f.mp3"))
      storage.upload_local_file(local_path)
    end

    it "uploads to every enabled bucket at that bucket's key" do
      add_mirror
      expect(stub_client).to receive(:put_object)
        .with(hash_including(bucket: "bb-backup", key: "mirror/bookmarks/s3_storage_spec/f.mp3"))
      allow(stub_client).to receive(:put_object).with(hash_including(bucket: "bb-archives"))
      storage.upload_local_file(local_path)
    end

    it "skips disabled buckets" do
      add_mirror(enabled: false)
      expect(stub_client).not_to receive(:put_object).with(hash_including(bucket: "bb-backup"))
      storage.upload_local_file(local_path)
    end

    it "sets the content type from the extension" do
      expect(stub_client).to receive(:put_object).with(hash_including(content_type: "audio/mpeg"))
      storage.upload_local_file(local_path)
    end

    it "doesn't re-upload an object a bucket already holds" do
      stub_client.stub_responses(:head_object, {content_length: 11})
      expect(stub_client).not_to receive(:put_object)
      storage.upload_local_file(local_path)
    end
  end

  describe "#delete_url" do
    before { add_mirror }

    it "deletes the primary bucket's copy" do
      expect(stub_client).to receive(:delete_object).with(bucket: "bb-archives", key: "bookmarks/abc/f.mp3")
      allow(stub_client).to receive(:delete_object).with(hash_including(bucket: "bb-backup"))
      storage.delete_url("s3://bb-archives/bookmarks/abc/f.mp3")
    end

    it "deletes every enabled bucket's copy of an s3 url" do
      expect(stub_client).to receive(:delete_object).with(bucket: "bb-backup", key: "mirror/bookmarks/abc/f.mp3")
      allow(stub_client).to receive(:delete_object).with(hash_including(bucket: "bb-archives"))
      storage.delete_url("s3://bb-archives/bookmarks/abc/f.mp3")
    end

    it "accepts a web path" do
      expect(stub_client).to receive(:delete_object).with(bucket: "bb-archives", key: "bookmarks/abc/f.mp3")
      allow(stub_client).to receive(:delete_object).with(hash_including(bucket: "bb-backup"))
      storage.delete_url("/archives/bookmarks/abc/f.mp3")
    end

    it "ignores s3 urls for buckets it doesn't know" do
      expect(stub_client).not_to receive(:delete_object)
      storage.delete_url("s3://someone-else/bookmarks/abc/f.mp3")
    end
  end

  describe "#delete_prefix" do
    before do
      stub_client.stub_responses(:list_objects_v2, {
        contents: [{key: "bookmarks/abc/a.mp3"}, {key: "bookmarks/abc/b.png"}],
        is_truncated: false
      })
    end

    it "deletes every object under the prefix" do
      expect(stub_client).to receive(:delete_objects).with(
        bucket: "bb-archives",
        delete: {objects: [{key: "bookmarks/abc/a.mp3"}, {key: "bookmarks/abc/b.png"}], quiet: true}
      ).and_call_original
      storage.delete_prefix("archives/bookmarks/abc/")
    end

    it "returns the number deleted" do
      expect(storage.delete_prefix("archives/bookmarks/abc/")).to eq(2)
    end

    it "counts the copies deleted from every enabled bucket" do
      add_mirror
      expect(storage.delete_prefix("archives/bookmarks/abc/")).to eq(4)
    end

    it "lists each bucket under its own key prefix" do
      add_mirror
      expect(stub_client).to receive(:list_objects_v2)
        .with(hash_including(bucket: "bb-backup", prefix: "mirror/bookmarks/abc/")).and_call_original
      allow(stub_client).to receive(:list_objects_v2)
        .with(hash_including(bucket: "bb-archives")).and_call_original
      storage.delete_prefix("archives/bookmarks/abc/")
    end

    it "refuses a prefix that isn't a folder" do
      expect { storage.delete_prefix("archives/bookmarks/abc") }.to raise_error(ArgumentError)
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

    it "uses the bucket's expiry" do
      expect(url).to include("X-Amz-Expires=600")
    end

    it "can be given a shorter expiry" do
      expect(storage.presigned_url("bookmarks/abc/f.mp3", expires_in: 300)).to include("X-Amz-Expires=300")
    end

    it "signs for the given bucket" do
      mirror = add_mirror
      expect(storage.presigned_url("mirror/bookmarks/abc/f.mp3", mirror))
        .to start_with("http://localhost:9000/bb-backup/mirror/bookmarks/abc/f.mp3?")
    end
  end
end
