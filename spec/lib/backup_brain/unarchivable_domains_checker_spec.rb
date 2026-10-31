require "rails_helper"
require "tempfile"

RSpec.describe BackupBrain::UnarchivableDomainsChecker do
  let(:config_file) do
    file = Tempfile.new(["unarchivable_domains", ".yml"])
    file.write(domains.to_yaml)
    file.flush
    file
  end
  let(:domains) { ["reddit.com", "www.Example.org"] }
  let(:checker) { described_class.new(config_file.path) }

  after { config_file.close! }

  describe ".instance" do
    it "loads the real config without error" do
      expect(described_class.reload!.maybe_archivable?("https://example.com/")).to be(true)
    end
  end

  describe "#maybe_archivable?" do
    it "is true for an unlisted domain" do
      expect(checker.maybe_archivable?("https://example.com/foo")).to be(true)
    end

    it "is false for a listed domain" do
      expect(checker.maybe_archivable?("https://reddit.com/r/ruby")).to be(false)
    end

    it "is false for www. on a listed domain" do
      expect(checker.maybe_archivable?("https://www.reddit.com/r/ruby")).to be(false)
    end

    it "is false for other subdomains of a listed domain" do
      expect(checker.maybe_archivable?("https://old.reddit.com/r/ruby")).to be(false)
    end

    it "ignores case in the url" do
      expect(checker.maybe_archivable?("https://WWW.Reddit.COM/r/ruby")).to be(false)
    end

    it "ignores case and a www. prefix in the config" do
      expect(checker.maybe_archivable?("https://example.org/")).to be(false)
    end

    it "doesn't match domains that merely end with a listed domain" do
      expect(checker.maybe_archivable?("https://notreddit.com/")).to be(true)
    end

    it "doesn't match a listed domain appearing elsewhere in the url" do
      expect(checker.maybe_archivable?("https://example.com/?ref=reddit.com")).to be(true)
    end

    it "accepts a URI" do
      expect(checker.maybe_archivable?(URI.parse("https://reddit.com/"))).to be(false)
    end

    it "is false for nil" do
      expect(checker.maybe_archivable?(nil)).to be(false)
    end

    it "is false for a blank string" do
      expect(checker.maybe_archivable?("  ")).to be(false)
    end

    it "is false for an unparseable url" do
      expect(checker.maybe_archivable?("https://exa mple.com/")).to be(false)
    end

    context "when the config file is missing" do
      let(:checker) { described_class.new(Rails.root.join("tmp/no_such_file.yml")) }

      it "treats every domain as potentially archivable" do
        expect(checker.maybe_archivable?("https://reddit.com/")).to be(true)
      end
    end

    context "when the config file is empty" do
      let(:domains) { nil }

      it "treats every domain as potentially archivable" do
        expect(checker.maybe_archivable?("https://reddit.com/")).to be(true)
      end
    end
  end
end
