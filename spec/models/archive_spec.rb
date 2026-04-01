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

  describe ".extract_video_urls_from_line" do
    context "with no video URLs" do
      it "returns the line unchanged and an empty hash" do
        line = "just some text"
        result_line, hashes = described_class.extract_video_urls_from_line(line)
        expect(result_line).to eq(line)
        expect(hashes).to be_empty
      end
    end

    context "with a youtube.com/watch URL" do
      let(:url)  { "https://www.youtube.com/watch?v=eaYOPO7sXBc" }
      let(:line) { url }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "stores extension: nil" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.first[:extension]).to be_nil
      end

      it "uses the SHA256 of the URL as the hash key" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.keys.first).to eq(Digest::SHA2.hexdigest(url))
      end

      it "replaces the URL with its hash in the returned line" do
        result_line, hashes = described_class.extract_video_urls_from_line(line)
        expect(result_line).to include(hashes.keys.first)
        expect(result_line).not_to include(url)
      end
    end

    context "with a youtu.be short URL" do
      let(:url)  { "https://youtu.be/eaYOPO7sXBc" }
      let(:line) { url }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "stores extension: nil" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.first[:extension]).to be_nil
      end
    end

    context "with a YouTube URL appearing twice as [URL](URL)" do
      let(:url)  { "https://www.youtube.com/watch?v=eaYOPO7sXBc" }
      let(:line) { "[#{url}](#{url})" }

      it "produces only one hash entry" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to eq([url])
      end

      it "replaces both occurrences in the returned line" do
        result_line, _ = described_class.extract_video_urls_from_line(line)
        expect(result_line).not_to include(url)
        expect(result_line.scan(Digest::SHA2.hexdigest(url)).length).to eq(2)
      end
    end

    context "with a src= URL that has a recognised video extension" do
      let(:url)  { "https://example.com/clip.mp4" }
      let(:line) { %(<video src="#{url}"></video>) }

      it "extracts the URL into the hash" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end

      it "includes the extension in the hash value" do
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.first[:extension]).to eq(".mp4")
      end

      it "replaces the URL with its hash in the returned line" do
        result_line, hashes = described_class.extract_video_urls_from_line(line)
        expect(result_line).to include(hashes.keys.first)
        expect(result_line).not_to include(url)
      end
    end

    context "with a relative src= URL" do
      it "matches absolute-path relative URLs" do
        url = "/videos/clip.mp4"
        line = %(<video src="#{url}"></video>)
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end
    end

    context "with multiple video URLs on one line" do
      it "extracts all URLs" do
        url1 = "https://example.com/clip1.mp4"
        url2 = "https://example.com/clip2.webm"
        line = %(<video src="#{url1}"></video><video src="#{url2}"></video>)
        _, hashes = described_class.extract_video_urls_from_line(line)
        expect(hashes.values.map { |v| v[:url] }).to contain_exactly(url1, url2)
      end

      it "replaces all URLs with their hashes" do
        url1 = "https://example.com/clip1.mp4"
        url2 = "https://example.com/clip2.webm"
        line = %(<video src="#{url1}"></video><video src="#{url2}"></video>)
        result_line, _ = described_class.extract_video_urls_from_line(line)
        expect(result_line).not_to include(url1)
        expect(result_line).not_to include(url2)
      end
    end

    context "with replace: false" do
      it "does not modify the line" do
        url = "https://example.com/clip.mp4"
        line = %(<video src="#{url}"></video>)
        result_line, hashes = described_class.extract_video_urls_from_line(line, false)
        expect(result_line).to eq(line)
        expect(hashes.values.map { |v| v[:url] }).to include(url)
      end
    end

    context "with each supported video extension" do
      described_class::VIDEO_EXTENSIONS.each do |ext|
        it "matches .#{ext}" do
          url = "https://example.com/clip.#{ext}"
          line = %(<video src="#{url}"></video>)
          _, hashes = described_class.extract_video_urls_from_line(line)
          expect(hashes.values.map { |v| v[:url] }).to include(url)
        end
      end
    end
  end

  describe "#image_urls" do
    it "returns an empty array when mime_type is not text/markdown" do
      archive = described_class.new(mime_type: "text/html", string_data: "![](https://example.com/img.jpg)")
      expect(archive.image_urls).to eq([])
    end

    it "returns an empty array when there are no images" do
      archive = described_class.new(mime_type: "text/markdown", string_data: "just text")
      expect(archive.image_urls).to eq([])
    end

    it "returns image URLs found in string_data" do
      url = "https://example.com/img.jpg"
      archive = described_class.new(mime_type: "text/markdown", string_data: "![alt](#{url})")
      expect(archive.image_urls).to contain_exactly(url)
    end

    it "returns URLs from multiple lines" do
      url1 = "https://example.com/img1.jpg"
      url2 = "https://example.com/img2.png"
      archive = described_class.new(mime_type: "text/markdown", string_data: "![](#{url1})\n![](#{url2})")
      expect(archive.image_urls).to contain_exactly(url1, url2)
    end
  end

  describe "#audio_urls" do
    it "returns an empty array when mime_type is not text/markdown" do
      archive = described_class.new(mime_type: "text/html", string_data: %(<source src="https://example.com/audio.mp3" />))
      expect(archive.audio_urls).to eq([])
    end

    it "returns an empty array when there are no audio URLs" do
      archive = described_class.new(mime_type: "text/markdown", string_data: "just text")
      expect(archive.audio_urls).to eq([])
    end

    it "returns audio URLs found in string_data" do
      url = "https://example.com/audio.mp3"
      archive = described_class.new(mime_type: "text/markdown", string_data: %(<source src="#{url}" />))
      expect(archive.audio_urls).to contain_exactly(url)
    end

    it "returns URLs from multiple lines" do
      url1 = "https://example.com/audio1.mp3"
      url2 = "https://example.com/audio2.wav"
      archive = described_class.new(
        mime_type: "text/markdown",
        string_data: %(<source src="#{url1}" />\n<source src="#{url2}" />)
      )
      expect(archive.audio_urls).to contain_exactly(url1, url2)
    end
  end

  describe "#video_urls" do
    it "returns an empty array when mime_type is not text/markdown" do
      archive = described_class.new(mime_type: "text/html", string_data: %(<video src="https://example.com/clip.mp4"></video>))
      expect(archive.video_urls).to eq([])
    end

    it "returns an empty array when there are no video URLs" do
      archive = described_class.new(mime_type: "text/markdown", string_data: "just text")
      expect(archive.video_urls).to eq([])
    end

    it "returns video src URLs found in string_data" do
      url = "https://example.com/clip.mp4"
      archive = described_class.new(mime_type: "text/markdown", string_data: %(<video src="#{url}"></video>))
      expect(archive.video_urls).to contain_exactly(url)
    end

    it "returns YouTube URLs found in string_data" do
      url = "https://www.youtube.com/watch?v=eaYOPO7sXBc"
      archive = described_class.new(mime_type: "text/markdown", string_data: url)
      expect(archive.video_urls).to contain_exactly(url)
    end

    it "returns URLs from multiple lines" do
      url1 = "https://example.com/clip.mp4"
      url2 = "https://www.youtube.com/watch?v=eaYOPO7sXBc"
      archive = described_class.new(mime_type: "text/markdown", string_data: "#{url2}\n<video src=\"#{url1}\"></video>")
      expect(archive.video_urls).to contain_exactly(url1, url2)
    end
  end

  describe "#media_urls" do
    it "returns an empty array when there are no audio or video URLs" do
      archive = described_class.new(mime_type: "text/markdown", string_data: "just text")
      expect(archive.media_urls).to eq([])
    end

    it "returns audio URLs" do
      url = "https://example.com/audio.mp3"
      archive = described_class.new(mime_type: "text/markdown", string_data: %(<source src="#{url}" />))
      expect(archive.media_urls).to contain_exactly(url)
    end

    it "returns video URLs" do
      url = "https://example.com/clip.mp4"
      archive = described_class.new(mime_type: "text/markdown", string_data: %(<video src="#{url}"></video>))
      expect(archive.media_urls).to contain_exactly(url)
    end

    it "returns both audio and video URLs together" do
      audio_url = "https://example.com/audio.mp3"
      video_url = "https://example.com/clip.mp4"
      archive = described_class.new(
        mime_type: "text/markdown",
        string_data: %(<source src="#{audio_url}" />\n<video src="#{video_url}"></video>)
      )
      expect(archive.media_urls).to contain_exactly(audio_url, video_url)
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
