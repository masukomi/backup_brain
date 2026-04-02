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
  before do
    allow(bookmark).to receive(:save!)
    allow(instance).to receive_messages(missing_audio_audio_url: "/audio/missing_audio_audio.mp3", missing_image_image_url: "/images/icons/missing_image_image.svg")
  end

  describe "#download_asset" do
    let(:url) { "https://example.com/audio.mp3" }
    let(:tmpdir) { Dir.mktmpdir }

    before do
      allow(instance).to receive_messages(archive_folder_path_for_doc: tmpdir, archive_web_path_for_doc: "/archives/bookmarks/test_id")
    end

    after { FileUtils.remove_entry(tmpdir) }

    context "when the file already exists locally" do
      before do
        local_name = instance.archived_image_name(url)
        FileUtils.touch(File.join(tmpdir, local_name))
      end

      it "returns the web path without downloading", :aggregate_failures do
        local_name = instance.archived_image_name(url)
        expect(HTTParty).not_to receive(:get)
        result = instance.download_asset(bookmark, url, asset_label: "audio")
        expect(result).to eq("/archives/bookmarks/test_id/#{local_name}")
      end
    end

    context "when download is successful" do
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

    # rubocop:disable RSpec/VerifiedDoubles
    context "when extension is nil and the response Content-Type reveals the type" do
      let(:url) { "https://cdn.example.com/?t=TOKEN&st=SIG" }
      let(:fake_response) { double("HTTPartyResponse", headers: {"content-type" => "audio/wav"}) }

      before do
        allow(HTTParty).to receive(:get).and_yield("audio bytes").and_return(fake_response)
      end

      it "returns a path ending in the extension from the Content-Type header" do
        result = instance.download_asset(bookmark, url, asset_label: "audio", extension: nil)
        expect(result).to end_with(".wav")
      end

      it "does not call detect_file_extension" do
        expect(instance).not_to receive(:detect_file_extension)
        instance.download_asset(bookmark, url, asset_label: "audio", extension: nil)
      end
    end
    # rubocop:enable RSpec/VerifiedDoubles

    context "when extension is nil, Content-Type is absent, and no prior file exists" do
      let(:url) { "https://cdn.example.com/?t=TOKEN&st=SIG" }

      before do
        allow(HTTParty).to receive(:get).and_yield("audio bytes")
        allow(instance).to receive(:detect_file_extension).and_return(".wav")
      end

      it "falls back to file(1) detection and returns a path ending in the detected extension" do
        result = instance.download_asset(bookmark, url, asset_label: "audio", extension: nil)
        expect(result).to end_with(".wav")
      end
    end

    context "when extension is nil and a previously-detected file already exists" do
      let(:url) { "https://cdn.example.com/?t=TOKEN&st=SIG" }
      let(:hex) { Digest::SHA2.hexdigest(url) }

      before do
        FileUtils.touch(File.join(tmpdir, "#{hex}.wav"))
      end

      it "returns the existing file path without re-downloading", :aggregate_failures do
        expect(HTTParty).not_to receive(:get)
        result = instance.download_asset(bookmark, url, asset_label: "audio", extension: nil)
        expect(result).to end_with("#{hex}.wav")
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
        begin
          instance.download_asset(bookmark, url, asset_label: "audio")
        rescue
          nil
        end
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

    context "when the url is a streaming url" do
      let(:hls_url) { "https://stream.example.com/playlist.m3u8" }

      it "delegates to download_audio_stream" do
        expect(instance).to receive(:download_audio_stream).with(bookmark, hls_url, extension: nil)
        instance.download_audio(bookmark, hls_url)
      end

      it "does not call url_downloadable?" do
        allow(instance).to receive(:download_audio_stream)
        expect(instance).not_to receive(:url_downloadable?)
        instance.download_audio(bookmark, hls_url)
      end
    end

    context "when the url is not downloadable" do
      before { allow(instance).to receive(:url_downloadable?).with(url, include_code: true).and_return([false, 403]) }

      it "returns missing_audio_audio_url" do
        expect(instance.download_audio(bookmark, url)).to eq("/audio/missing_audio_audio.mp3")
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

    context "when successful" do
      before do
        allow(instance).to receive_messages(url_downloadable?: [true, 200], download_asset: local_url)
      end

      it "returns the local web path" do
        expect(instance.download_audio(bookmark, url)).to eq(local_url)
      end
    end
  end

  describe "#streaming_url?" do
    it "returns true for an .m3u8 url" do
      expect(instance.streaming_url?("https://stream.example.com/playlist.m3u8")).to be true
    end

    it "returns true for an .mpd url" do
      expect(instance.streaming_url?("https://stream.example.com/manifest.mpd")).to be true
    end

    it "returns false for a direct audio url" do
      expect(instance.streaming_url?("https://example.com/audio.mp3")).to be false
    end

    it "returns false for a signed CDN url with no path extension" do
      expect(instance.streaming_url?("https://stream.example.com/?t=TOKEN&st=SIG")).to be false
    end
  end

  describe "#archived_image_name" do
    it "strips the query string before hashing for normal URLs" do
      url = "https://example.com/audio.mp3?token=abc"
      name_with_qs    = instance.archived_image_name(url)
      name_without_qs = instance.archived_image_name("https://example.com/audio.mp3")
      expect(name_with_qs).to eq(name_without_qs)
    end

    it "includes the query string in the hash when the path is only '/'" do
      url1 = "https://stream.example.com/?t=TOKEN1&st=SIG1"
      url2 = "https://stream.example.com/?t=TOKEN2&st=SIG2"
      expect(instance.archived_image_name(url1)).not_to eq(instance.archived_image_name(url2))
    end

    it "uses a provided extension over the one in the URL" do
      url = "https://example.com/audio.mp3"
      name = instance.archived_image_name(url, ".wav")
      expect(name).to end_with(".wav")
    end

    it "adds a leading dot to the extension if missing" do
      name = instance.archived_image_name("https://example.com/audio.mp3", "wav")
      expect(name).to end_with(".wav")
    end
  end

  describe "#download_image" do
    let(:url) { "https://example.com/image.jpg" }
    let(:local_url) { "/archives/bookmarks/test_id/hash.jpg" }

    context "with a data: URI" do
      it "returns the data URI unchanged without any network call", :aggregate_failures do
        data_url = "data:image/png;base64,abc123"
        expect(HTTParty).not_to receive(:head)
        expect(instance.download_image(bookmark, data_url)).to eq(data_url)
      end
    end

    context "when the url is not downloadable" do
      before { allow(instance).to receive(:url_downloadable?).with(url, include_code: true).and_return([false, 404]) }

      it "returns missing_image_image_url" do
        allow(instance).to receive(:record_failed_attempt)
        expect(instance.download_image(bookmark, url)).to eq("/images/icons/missing_image_image.svg")
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

    context "when successful" do
      before do
        allow(instance).to receive_messages(url_downloadable?: [true, 200], download_asset: local_url)
      end

      it "returns the local web path" do
        expect(instance.download_image(bookmark, url)).to eq(local_url)
      end
    end
  end

  describe "#qualify_and_apply_audio_url_hashes" do
    let(:domain) { "https://example.com" }
    let(:directory) { "https://example.com" }

    context "when the stored url is missing_audio_audio_url" do
      it "does not attempt to download" do
        sha = Digest::SHA2.hexdigest("original")
        hashes = {sha => {url: "/audio/missing_audio_audio.mp3", extension: ".mp3"}}
        expect(instance).not_to receive(:download_audio)
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end

      it "substitutes the hash with missing_audio_audio_url in the line", :aggregate_failures do
        sha = Digest::SHA2.hexdigest("original")
        missing = "/audio/missing_audio_audio.mp3"
        hashes = {sha => {url: missing, extension: ".mp3"}}
        result = instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
        expect(result).to include(missing)
        expect(result).not_to include(sha)
      end
    end

    context "when the url is already a local archive path" do
      it "does not attempt to download" do
        local_url = "#{instance.archive_web_path_for_doc(bookmark)}/hash.mp3"
        sha = Digest::SHA2.hexdigest(local_url)
        hashes = {sha => {url: local_url, extension: ".mp3"}}
        expect(instance).not_to receive(:download_audio)
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "with a remote audio url" do
      let(:remote_url) { "https://example.com/audio.mp3" }
      let(:local_url) { "#{instance.archive_web_path_for_doc(bookmark)}/hash.mp3" }

      before { allow(instance).to receive(:download_audio).and_return(local_url) }

      it "replaces the hash with the local url", :aggregate_failures do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => {url: remote_url, extension: ".mp3"}}
        result = instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
        expect(result).to include(local_url)
        expect(result).not_to include(sha)
      end

      it "calls download_audio with the fully qualified url and extension" do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => {url: remote_url, extension: ".mp3"}}
        expect(instance).to receive(:download_audio).with(bookmark, remote_url, extension: ".mp3")
        instance.qualify_and_apply_audio_url_hashes(bookmark, hashes, %(src="#{sha}"), domain, directory)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe "#qualify_and_apply_image_url_hashes" do
    let(:domain) { "https://example.com" }
    let(:directory) { "https://example.com" }

    context "when the stored url is missing_image_image_url" do
      it "does not attempt to download" do
        sha = Digest::SHA2.hexdigest("original")
        hashes = {sha => {url: "/images/icons/missing_image_image.svg", extension: ".svg"}}
        expect(instance).not_to receive(:download_image)
        instance.qualify_and_apply_image_url_hashes(bookmark, hashes, "![](#{sha})", domain, directory)
      end

      it "substitutes the hash with the missing image markdown" do
        sha = Digest::SHA2.hexdigest("original")
        missing = "/images/icons/missing_image_image.svg"
        hashes = {sha => {url: missing, extension: ".svg"}}
        result = instance.qualify_and_apply_image_url_hashes(bookmark, hashes, sha.dup, domain, directory)
        expect(result).to eq("![](#{missing})")
      end
    end

    # rubocop:disable RSpec/MultipleMemoizedHelpers
    context "with a remote image url" do
      let(:remote_url) { "https://example.com/image.jpg" }
      let(:local_url) { "/archives/bookmarks/test_id/hash.jpg" }

      before { allow(instance).to receive(:download_image).and_return(local_url) }

      it "replaces the hash with image markdown pointing at the local url" do
        sha = Digest::SHA2.hexdigest(remote_url)
        hashes = {sha => {url: remote_url, extension: ".jpg"}}
        result = instance.qualify_and_apply_image_url_hashes(bookmark, hashes, sha.dup, domain, directory)
        expect(result).to eq("![](#{local_url})")
      end
    end
    # rubocop:enable RSpec/MultipleMemoizedHelpers
  end
end
