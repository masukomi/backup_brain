require "rails_helper"

RSpec.describe ArchiveUrlJob do
  let(:bookmark) { Bookmark.new(url: "https://example.com/foo/") }
  let(:job) { described_class.new }
  # describe '#perform' do
  #   let(:url) { 'http://example.com' }
  #   let(:job) { described_class.new }

  #   it 'calls the ArchiveUrlService' do
  #     expect(ArchiveUrlService).to receive(:call).with(url)
  #     job.perform(url)
  #   end
  # end

  describe "#get_directory_url" do
    it "handles urls that end in slashes" do
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo/")
      )).to(eq("https://example.com/foo"))
    end

    it "handles urls that don't end in slashes", :aggregate_failures do
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo")
      )).to(eq("https://example.com"))
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo/bar")
      )).to(eq("https://example.com/foo"))
    end

    it "handles urls that end in slashes & query strings" do
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo/?this=that&no=yes")
      )).to(eq("https://example.com/foo"))
    end

    it "handles urls that don't end in slashes & query strings", :aggregate_failures do
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo?this=that&no=yes")
      )).to(eq("https://example.com"))
      expect(job.get_directory_url(
        Bookmark.new(url: "https://example.com/foo/bar?this=that&no=yes")
      )).to(eq("https://example.com/foo"))
    end
  end

  describe "#fully_qualify_urls" do
    let(:markdown) {
      <<~MD
        this line 1 [link](https://example.com/coolness) has one fully qualified link
        this line 2 [link](/bar) has one absolute link
        this line 3 [link](bar) has one relative link
        this line 4 [link1](foo), ![link2](/boo.jpg) has two & one's an image
        [line 5](foo), starts & ends with a [link2](/boo.jpg)
        [![an_image](/image.png)](/thats/a/link)
      MD
    }
    let(:processed_lines) {
      job.fully_qualify_urls(markdown, bookmark).split("\n")
    }

    it "retains the number of lines" do
      expect(processed_lines.size).to(eq(6))
    end

    it "leaves fully qualified paths alone" do
      expect(processed_lines[0]).to(
        eq("this line 1 [link](https://example.com/coolness) has one fully qualified link")
      )
    end

    it "handles lines with only one link", :aggregate_failures do
      expect(processed_lines[1]).to(
        eq("this line 2 [link](https://example.com/bar) has one absolute link")
      )
      expect(processed_lines[2]).to(
        eq("this line 3 [link](https://example.com/foo/bar) has one relative link")
      )
    end

    it "handles lines with multiple links", :aggregate_failures do
      line_4 = "this line 4 [link1](https://example.com/foo/foo), ![link2](https://example.com/boo.jpg) has two & one's an image"

      line_5 = "[line 5](https://example.com/foo/foo), starts & ends with a [link2](https://example.com/boo.jpg)"

      expect(processed_lines[3]).to(eq(line_4))
      expect(processed_lines[4]).to(eq(line_5))
    end

    it "handles images in links" do
      line_6 = "[![an_image](https://example.com/image.png)](https://example.com/thats/a/link)"
      expect(processed_lines[5]).to(eq(line_6))
    end
  end

  describe "#fully_qualify_path" do
    let(:domain) { "https://example.com" }
    let(:directory) { "https://example.com/foo" }

    it "handles relative paths correctly", :aggregate_failures do
      expect(job.fully_qualify_path(
        "boo.jpg", domain, directory
      )).to(eq("https://example.com/foo/boo.jpg"))
      expect(job.fully_qualify_path(
        "../boo.jpg", domain, directory
      )).to(eq("https://example.com/foo/../boo.jpg"))
    end

    it "handles absolute paths correctly", :aggregate_failures do
      expect(job.fully_qualify_path(
        "/boo.jpg", domain, directory
      )).to(eq("https://example.com/boo.jpg"))
      expect(job.fully_qualify_path(
        "/boo", domain, directory
      )).to(eq("https://example.com/boo"))
    end
  end

  describe "#download" do
    # TODO: figure out how to make a string I can test this with.
    # The goal here is to test this code
    #   file.write(response
    #                .body
    #                .encode!('UTF-8', 'binary',
    #                         invalid: :replace,
    #                         undef: :replace,
    #                         replace: '')
    #             )
    # it WAS blowing up when trying to write
    # https://blog.pinboard.in/2017/06/pinboard_acquires_delicious/
    # to the temp file, so I added that funky .encode!(…) stuff
    it "doesn't break when encountering a badly encoded response body"
  end
end
