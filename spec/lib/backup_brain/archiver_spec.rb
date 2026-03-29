require "spec_helper"
require "rails_helper"

class FakeArchiverModel
  include BackupBrain::ArchiveTools
  include BackupBrain::Archiver
end

RSpec.describe BackupBrain::Archiver do
  let(:instance) { FakeArchiverModel.new }
  let(:bookmark) { Bookmark.new(url: "https://example.com/page") }

  # Prevent any real DB writes that come from record_failed_attempt
  before { allow(bookmark).to receive(:save!) }

  describe "#download_asset" do
    let(:url) { "https://example.com/audio.mp3" }
    let(:tmpdir) { Dir.mktmpdir }

    before do
      allow(instance).to receive(:archive_folder_path_for_doc).and_return(tmpdir)
      allow(instance).to receive(:archive_web_path_for_doc).and_return("/archives/bookmarks/test_id")
    end

    after { FileUtils.remove_entry(tmpdir) }

    context "when the file already exists locally" do
      before do
        local_name = instance.archived_image_name(url)
        FileUtils.touch(File.join(tmpdir, local_name))
      end

      it "returns the web path without downloading" do
        local_name = instance.archived_image_name(url)
        expect(HTTParty).not_to receive(:get)
        result = instance.download_asset(bookmark, url, asset_label: "audio")
        expect(result).to eq("/archives/bookmarks/test_id/#{local_name}")
      end
    end

    context "on a successful download" do
      before { allow(HTTParty).to receive(:get).and_yield("audio bytes") }

      it "returns the new local web path" do
        local_name = instance.archived_image_name(url)
        result = instance.download_asset(bookmark, url, asset_label: "audio")
        expect(result).to eq("/archives/bookmarks/test_id/#{local_name}")
      end

      it "writes the downloaded content to disk" do
        local_name = instance.archived_image_name(url)
        instance.download_asset(bookmark, url, asset_label: "audio")
        expect(File.read(File.join(tmpdir, local_name))).to eq("audio bytes")
      end
    end

    context "when directory creation fails" do
      before { allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EACCES, "permission denied") }

      it "raises a StorageError" do
        expect {
          instance.download_asset(bookmark, url, asset_label: "audio")
        }.to raise_error(BackupBrain::Errors::StorageError)
      end
    end

    context "when the download raises" do
      before { allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout) }

      it "logs a warning mentioning the asset label" do
        expect(Rails.logger).to receive(:warn).with(/audio/)
        instance.download_asset(bookmark, url, asset_label: "audio") rescue nil
      end

      it "re-raises the exception" do
        expect {
          instance.download_asset(bookmark, url, asset_label: "audio")
        }.to raise_error(Net::ReadTimeout)
      end
    end
  end

  describe "#download_audio" do
    let(:url) { "https://example.com/audio.mp3" }
    let(:local_url) { "/archives/bookmarks/test_id/hash.mp3" }

    context "when the url is not downloadable" do
      before { allow(instance).to receive(:url_downloadable?).with(url, include_code: true).and_return([false, 403]) }

      it "returns MISSING_AUDIO_AUDIO_URL" do
        expect(instance.download_audio(bookmark, url)).to eq(described_class::MISSING_AUDIO_AUDIO_URL)
      end

      it "records a failed attempt with the error code" do
        expect(instance).to receive(:record_failed_attempt).with(bookmark, 403, hash_including(should_raise: false))
        instance.download_audio(bookmark, url)
      end

      it "does not raise" do
        allow(instance).to receive(:record_failed_attempt)
        expect { instance.download_audio(bookmark, url) }.not_to raise_error
      end
    end

    context "when download_asset raises" do
      before do
        allow(instance).to receive(:url_downloadable?).and_return([true, 200])
        allow(instance).to receive(:download_asset).and_raise(StandardError, "write failed")
      end

      it "returns the original url rather than raising" do
        expect(instance.download_audio(bookmark, url)).to eq(url)
      end
    end

    context "on success" do
      before do
        allow(instance).to receive(:url_downloadable?).and_return([true, 200])
        allow(instance).to receive(:download_asset).and_return(local_url)
      end

      it "returns the local web path" do
        expect(instance.download_audio(bookmark, url)).to eq(local_url)
      end
    end
  end

  describe "#download_image" do
    let(:url) { "https://example.com/image.jpg" }
    let(:local_url) { "/archives/bookmarks/test_id/hash.jpg" }

    context "with a data: URI" do
      it "returns the data URI unchanged without any network call" do
        data_url = "data:image/png;base64,abc123"
        expect(HTTParty).not_to receive(:head)
        expect(instance.download_image(bookmark, data_url)).to eq(data_url)
      end
    end

    context "when the url is not downloadable" do
      before { allow(instance).to receive(:url_downloadable?).with(url, include_code: true).and_return([false, 404]) }

      it "returns MISSING_IMAGE_IMAGE_URL" do
        allow(instance).to receive(:record_failed_attempt)
        expect(instance.download_image(bookmark, url)).to eq(described_class::MISSING_IMAGE_IMAGE_URL)
      end

      it "records a failed attempt" do
        expect(instance).to receive(:record_failed_attempt).with(bookmark, 404, anything)
        instance.download_image(bookmark, url)
      end
    end

    context "when download_asset raises" do
      before do
        allow(instance).to receive(:url_downloadable?).and_return([true, 200])
        allow(instance).to receive(:download_asset).and_raise(Net::ReadTimeout)
      end

      it "re-raises the error" do
        expect { instance.download_image(bookmark, url) }.to raise_error(Net::ReadTimeout)
      end
    end

    context "on success" do
      before do
        allow(instance).to receive(:url_downloadable?).and_return([true, 200])
        allow(instance).to receive(:download_asset).and_return(local_url)
      end

      it "returns the local web path" do
        expect(instance.download_image(bookmark, url)).to eq(local_url)
      end
    end
  end

  describe "#qualify_and_apply_audio_url_hashes" do
    let(:domain) { "https://example.com" }
    let(:directory) { "https://example.com" }

    context "when the stored url is MISSING_AUDIO_AUDIO_URL" do
      it "does not attempt to download" do
        sha = Digest::SHA2.hexdigest("original")
        hashes = {sha => described_class::MISSING_AUDIO_AUDIO_URL}
        expect(instance).not_to receive(:download_audio)
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end

      it "substitutes the hash with MISSING_AUDIO_AUDIO_URL in the line" do
        sha = Digest::SHA2.hexdigest("original")
        missing = described_class::MISSING_AUDIO_AUDIO_URL
        hashes = {sha => missing}
        result = instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
        expect(result).to include(missing)
        expect(result).not_to include(sha)
      end
    end

    context "when the url is already a local archive path" do
      it "does not attempt to download" do
        local_url = "#{instance.archive_web_path_for_doc(bookmark)}/hash.mp3"
        sha = Digest::SHA2.hexdigest(local_url)
        hashes = {sha => local_url}
        expect(instance).not_to receive(:download_audio)
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end
    end

    context "with a remote audio url" do
      let(:remote_url) { "https://example.com/audio.mp3" }
      let(:local_url) { "#{instance.archive_web_path_for_doc(bookmark)}/hash.mp3" }

      before { allow(instance).to receive(:download_audio).and_return(local_url) }

      it "replaces the hash with the local url" do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => remote_url}
        result = instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
        expect(result).to include(local_url)
        expect(result).not_to include(sha)
      end

      it "calls download_audio with the fully qualified url" do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => remote_url}
        expect(instance).to receive(:download_audio).with(bookmark, remote_url)
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end
    end
  end

  describe "#qualify_and_apply_image_url_hashes" do
    let(:domain) { "https://example.com" }
    let(:directory) { "https://example.com" }

    context "when the stored url is MISSING_IMAGE_IMAGE_URL" do
      it "does not attempt to download" do
        sha = Digest::SHA2.hexdigest("original")
        hashes = {sha => described_class::MISSING_IMAGE_IMAGE_URL}
        expect(instance).not_to receive(:download_image)
        instance.qualify_and_apply_image_url_hashes(bookmark, hashes, "![](#{sha})", domain, directory)
      end

      it "substitutes the hash with the missing image markdown" do
        sha = Digest::SHA2.hexdigest("original")
        missing = described_class::MISSING_IMAGE_IMAGE_URL
        hashes = {sha => missing}
        result = instance.qualify_and_apply_image_url_hashes(bookmark, hashes, sha.dup, domain, directory)
        expect(result).to eq("![](#{missing})")
      end
    end

    context "with a remote image url" do
      let(:remote_url) { "https://example.com/image.jpg" }
      let(:local_url) { "/archives/bookmarks/test_id/hash.jpg" }

      before { allow(instance).to receive(:download_image).and_return(local_url) }

      it "replaces the hash with image markdown pointing at the local url" do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => remote_url}
        result = instance.qualify_and_apply_image_url_hashes(bookmark, hashes, sha.dup, domain, directory)
        expect(result).to eq("![](#{local_url})")
      end
    end
  end
end
