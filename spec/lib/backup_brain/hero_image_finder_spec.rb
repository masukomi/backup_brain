require "spec_helper"
require "rails_helper"

RSpec.describe BackupBrain::HeroImageFinder do
  describe ".find" do
    it "returns nil for blank input" do
      expect(described_class.find(nil)).to be_nil
      expect(described_class.find("")).to be_nil
    end

    it "returns nil when no hero image tag is present" do
      html = "<html><head><title>No image</title></head><body></body></html>"
      expect(described_class.find(html)).to be_nil
    end

    it "finds og:image via property attribute" do
      html = <<~HTML
        <html><head>
          <meta property="og:image" content="https://example.com/hero.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/hero.jpg")
    end

    it "finds og:image via name attribute" do
      html = <<~HTML
        <html><head>
          <meta name="og:image" content="https://example.com/hero.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/hero.jpg")
    end

    it "finds twitter:image via property attribute" do
      html = <<~HTML
        <html><head>
          <meta property="twitter:image" content="https://example.com/tweet.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/tweet.jpg")
    end

    it "finds twitter:image via name attribute" do
      html = <<~HTML
        <html><head>
          <meta name="twitter:image" content="https://example.com/tweet.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/tweet.jpg")
    end

    it "finds twitter:image:src via property attribute" do
      html = <<~HTML
        <html><head>
          <meta property="twitter:image:src" content="https://example.com/src.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/src.jpg")
    end

    it "finds itemprop image" do
      html = <<~HTML
        <html><head>
          <meta itemprop="image" content="https://example.com/schema.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/schema.jpg")
    end

    it "finds rel=image_src link tag" do
      html = <<~HTML
        <html><head>
          <link rel="image_src" href="https://example.com/link.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/link.jpg")
    end

    it "prefers og:image over twitter:image when both are present" do
      html = <<~HTML
        <html><head>
          <meta property="og:image" content="https://example.com/og.jpg" />
          <meta property="twitter:image" content="https://example.com/twitter.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/og.jpg")
    end

    it "returns a relative path when the content is relative" do
      html = <<~HTML
        <html><head>
          <meta property="og:image" content="/images/hero.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("/images/hero.jpg")
    end

    it "skips tags with empty content and falls through to the next" do
      html = <<~HTML
        <html><head>
          <meta property="og:image" content="" />
          <meta property="twitter:image" content="https://example.com/twitter.jpg" />
        </head></html>
      HTML
      expect(described_class.find(html)).to eq("https://example.com/twitter.jpg")
    end
  end
end
