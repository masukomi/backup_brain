require "rails_helper"

RSpec.describe Archive do
  describe ".extract_audio_urls_from_line" do
    context "with no audio src" do
      it "returns the line unchanged and an empty hash" do
        line = "just some text"
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to eq(line)
        expect(hashes).to be_empty
      end
    end

    context "with an audio src URL that has a recognised extension" do
      let(:url)  { "https://example.com/audio.mp3" }
      let(:line) { %(<source src="#{url}" />) }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "includes the extension in the hash value" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.first[:extension]).to eq(".mp3")
      end

      it "uses the SHA256 of the URL as the hash key" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.keys.first).to eq(Digest::SHA2.hexdigest(url))
      end

      it "replaces the URL with its hash in the returned line" do
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to include(hashes.keys.first)
        expect(result_line).not_to include(url)
      end
    end

    context "with a <source> tag whose type attribute is audio but URL has no audio extension" do
      let(:url)  { "https://stream.example.com/?t=TOKEN&st=SIG" }
      let(:line) { %(<source src="#{url}" type="audio/wav" />) }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "derives the extension from the type attribute" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.first[:extension]).to eq(".wav")
      end

      it "replaces the URL with its hash in the returned line" do
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to include(hashes.keys.first)
        expect(result_line).not_to include(url)
      end
    end

    context "with a <source> tag where type comes before src" do
      let(:url)  { "https://stream.example.com/?t=TOKEN" }
      let(:line) { %(<source type="audio/mp4" src="#{url}" />) }

      it "extracts the URL" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "derives the extension from the type attribute" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.first[:extension]).to eq(".m4a")
      end
    end

    context "with a relative URL" do
      it "matches absolute-path relative URLs" do
        url = "/sounds/audio.mp3"
        line = %(<source src="#{url}" />)
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end
    end

    context "with multiple audio sources on one line" do
      it "extracts all URLs" do
        url1 = "https://example.com/audio1.mp3"
        url2 = "https://example.com/audio2.m4a"
        line = %(<source src="#{url1}" /><source src="#{url2}" />)
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to contain_exactly(url1, url2)
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

    context "with an incomplete <source> tag (no closing > on this line)" do
      let(:url)  { "https://cdn.example.com/?t=TOKEN&st=SIG" }
      let(:line) { %(<source\n  src="#{url}") }

      it "extracts the URL" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "stores extension: nil" do
        _, hashes = described_class.extract_audio_urls_from_line(line)
        expect(hashes.values.first[:extension]).to be_nil
      end

      it "replaces the URL with its hash in the returned line" do
        result_line, hashes = described_class.extract_audio_urls_from_line(line)
        expect(result_line).to include(hashes.keys.first)
        expect(result_line).not_to include(url)
      end
    end

    context "with replace: false" do
      it "does not modify the line" do
        url = "https://example.com/audio.mp3"
        line = %(<source src="#{url}" />)
        result_line, hashes = described_class.extract_audio_urls_from_line(line, false)
        expect(result_line).to eq(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end
    end

    context "with each supported audio extension" do
      described_class::AUDIO_EXTENSIONS.each do |ext|
        it "matches .#{ext}" do
          url = "https://example.com/audio.#{ext}"
          line = %(<source src="#{url}" />)
          _, hashes = described_class.extract_audio_urls_from_line(line)
          expect(hashes.values.map { |v| v[:url] }).to include(url)
        end
      end
    end
  end

  describe ".extension_for_mime_type" do
    it "returns the extension for a known audio MIME type" do
      expect(described_class.extension_for_mime_type("audio/wav")).to eq(".wav")
    end

    it "returns the extension for audio/mpeg (mp3)" do
      expect(described_class.extension_for_mime_type("audio/mpeg")).to eq(".mp3")
    end

    it "strips codec parameters before lookup" do
      result = described_class.extension_for_mime_type("audio/ogg; codecs=opus")
      expect(result).to eq(".ogg").or eq(".oga")
    end

    it "returns nil for an unknown MIME type" do
      expect(described_class.extension_for_mime_type("application/octet-stream")).to be_nil
    end
  end
end
