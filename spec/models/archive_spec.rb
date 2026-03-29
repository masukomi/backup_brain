require "rails_helper"

RSpec.describe Archive do
  describe ".extract_audio_urls_from_line" do
    context "when no audio src is present" do
      it "returns the line unchanged and an empty hash" do
        line = "some plain text with no audio"
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to eq(line)
        expect(hashes).to be_empty
      end

      it "does not match image src attributes" do
        line = '<img src="photo.jpg" />'
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to eq(line)
        expect(hashes).to be_empty
      end

      it "does not match non-audio file extensions in src" do
        line = '<source src="https://example.com/video.mp4" />'
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes).to be_empty
      end
    end

    context "with a double-quoted src attribute" do
      let(:url) { "https://media.soundgasm.net/sounds/abc123.m4a" }
      let(:line) { %(<source src="#{url}" type="audio/mp4" />) }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values).to include(url)
      end

      it "replaces the URL in the line with a SHA256 hash" do
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        sha = hashes.keys.first
        expect(result_line).to include(%(src="#{sha}"))
        expect(result_line).not_to include(url)
      end

      it "uses the SHA256 of the URL as the hash key" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.keys.first).to eq(Digest::SHA2.hexdigest(url))
      end

      it "preserves the rest of the tag around the replaced URL" do
        result_line, _ = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to include('type="audio/mp4"')
      end
    end

    context "with a single-quoted src attribute" do
      it "extracts the URL" do
        url = "https://example.com/audio.mp3"
        line = %(<source src='#{url}' />)
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values).to include(url)
      end
    end

    context "with a relative URL" do
      it "matches absolute-path relative URLs" do
        url = "/sounds/audio.mp3"
        line = %(<source src="#{url}" />)
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values).to include(url)
      end
    end

    context "with multiple audio sources on one line" do
      it "extracts all URLs" do
        url1 = "https://example.com/audio1.mp3"
        url2 = "https://example.com/audio2.m4a"
        line = %(<source src="#{url1}" /><source src="#{url2}" />)
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values).to contain_exactly(url1, url2)
      end

      it "replaces all URLs with their hashes" do
        url1 = "https://example.com/audio1.mp3"
        url2 = "https://example.com/audio2.m4a"
        line = %(<source src="#{url1}" /><source src="#{url2}" />)
        result_line, _ = described_class.extract_audio_urls_from_line(line)
        expect(result_line).not_to include(url1)
        expect(result_line).not_to include(url2)
      end
    end

    context "with replace: false" do
      it "does not modify the line" do
        url = "https://example.com/audio.mp3"
        line = %(<source src="#{url}" />)
        result_line, hashes = described_class.extract_audio_urls_from_line(line, false)
        expect(result_line).to eq(line)
        expect(hashes.values).to include(url)
      end
    end

    context "with each supported audio extension" do
      described_class::AUDIO_EXTENSIONS.each do |ext|
        it "matches .#{ext}" do
          url = "https://example.com/audio.#{ext}"
          line = %(<source src="#{url}" />)
          _, hashes = described_class.extract_audio_urls_from_line(line)
          expect(hashes.values).to include(url)
        end
      end
    end
  end
end
