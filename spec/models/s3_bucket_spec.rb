require "rails_helper"

RSpec.describe S3Bucket do
  after do
    described_class.destroy_all
    BackupBrain::S3Storage.reload!
  end

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:s3_bucket)).to be_valid
    end

    it "requires a bucket name" do
      expect(build(:s3_bucket, name: "")).not_to be_valid
    end

    it "requires a nickname" do
      expect(build(:s3_bucket, nickname: nil)).not_to be_valid
    end

    it "requires a unique nickname" do
      create(:s3_bucket, nickname: "same")
      expect(build(:s3_bucket, nickname: "same")).not_to be_valid
    end

    it "requires credentials" do
      expect(build(:s3_bucket, secret_access_key: " ")).not_to be_valid
    end

    it "allows a blank endpoint (AWS)" do
      expect(build(:s3_bucket, endpoint: nil)).to be_valid
    end

    it "allows a blank key prefix (bucket root)" do
      expect(build(:s3_bucket, key_prefix: "")).to be_valid
    end

    it "allows a disabled bucket" do
      expect(build(:s3_bucket, enabled: false)).to be_valid
    end

    it "allows virtual-host style urls" do
      expect(build(:s3_bucket, path_style_urls: false)).to be_valid
    end

    it "caps the presigned url expiry at S3's limit" do
      expect(build(:s3_bucket, presigned_url_expiry: described_class::MAX_PRESIGNED_URL_EXPIRY + 1)).not_to be_valid
    end

    it "rejects a non-positive presigned url expiry" do
      expect(build(:s3_bucket, presigned_url_expiry: 0)).not_to be_valid
    end

    context "when a disabled bucket is marked primary" do
      let(:bucket) { build(:s3_bucket, enabled: false, primary: true) }

      before { bucket.valid? }

      it "is invalid" do
        expect(bucket).not_to be_valid
      end

      it "explains why" do
        expect(bucket.errors[:primary]).to include(I18n.t("s3_buckets.errors.enabled_primaries_only"))
      end
    end
  end

  describe "stripping" do
    it "strips whitespace from string fields before validating" do
      bucket = create(:s3_bucket, name: "  padded  ")
      expect(bucket.name).to eq("padded")
    end

    it "leaves nil strings alone" do
      expect(create(:s3_bucket, endpoint: nil).endpoint).to be_nil
    end
  end

  describe "primary bookkeeping" do
    it "makes the first enabled bucket the primary" do
      expect(create(:s3_bucket)).to be_primary
    end

    it "doesn't make a disabled bucket the primary" do
      expect(create(:s3_bucket, enabled: false)).not_to be_primary
    end

    it "leaves later enabled buckets as mirrors" do
      create(:s3_bucket)
      expect(create(:s3_bucket)).not_to be_primary
    end

    it "demotes the old primary when another bucket becomes primary" do
      first = create(:s3_bucket)
      create(:s3_bucket, primary: true)
      expect(first.reload).not_to be_primary
    end

    it "keeps exactly one primary" do
      create(:s3_bucket)
      create(:s3_bucket, primary: true)
      expect(described_class.where(primary: true).count).to eq(1)
    end
  end

  describe "class methods" do
    describe ".any_enabled?" do
      it "is false with no buckets" do
        expect(described_class.any_enabled?).to be(false)
      end

      it "is false when every bucket is disabled" do
        create(:s3_bucket, enabled: false)
        expect(described_class.any_enabled?).to be(false)
      end

      it "is true with an enabled bucket" do
        create(:s3_bucket)
        expect(described_class.any_enabled?).to be(true)
      end
    end

    describe ".primary_bucket" do
      it "is nil with no buckets" do
        expect(described_class.primary_bucket).to be_nil
      end

      it "returns the primary" do
        create(:s3_bucket)
        primary = create(:s3_bucket, primary: true)
        expect(described_class.primary_bucket).to eq(primary)
      end
    end

    describe ".enabled_buckets" do
      it "leaves out disabled buckets" do
        enabled = create(:s3_bucket)
        create(:s3_bucket, enabled: false)
        expect(described_class.enabled_buckets.to_a).to eq([enabled])
      end
    end
  end

  describe "keeping S3Storage current" do
    it "reloads S3Storage after a save" do
      allow(BackupBrain::S3Storage).to receive(:reload!)
      create(:s3_bucket)
      expect(BackupBrain::S3Storage).to have_received(:reload!)
    end

    it "reloads S3Storage after a destroy" do
      bucket = create(:s3_bucket)
      allow(BackupBrain::S3Storage).to receive(:reload!)
      bucket.destroy
      expect(BackupBrain::S3Storage).to have_received(:reload!)
    end
  end
end
