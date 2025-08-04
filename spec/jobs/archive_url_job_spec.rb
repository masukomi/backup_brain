require "rails_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe ArchiveUrlJob do
  # some variables aren't in let(:foo) because
  # we need to use them in the after(:all) and
  # that's not allowed, because reasons
  bookmark = Bookmark.new(url: "https://example.com/foo/")
  # let(:bookmark) { Bookmark.new(url: "https://example.com/foo/") }
  let(:job) { described_class.new }
  let(:bookmark_image_dir) { File.join("public", "images", "archival", bookmark._id.to_s) }
  let(:local_image_name) { "818dc04941a98ad317d198c067a1571a7d54c5d362eb31fe815f1fc64bbc26c1.png" }
  let(:bookmark_image_path) { File.join(bookmark_image_dir, local_image_name) }
  let(:local_image_url) { File.join(File::SEPARATOR, "images", "archival", bookmark._id.to_s, local_image_name) }
  let(:image_url) { "https://backupbrain.app/images/favicon.png" }

  bookmark_image_dir = File.join("public", "images", "archival", bookmark._id.to_s)

  # rubocop:disable RSpec/BeforeAfterAll
  after(:all) do
    FileUtils.rm_r(bookmark_image_dir, force: true) if File.exist?(bookmark_image_dir)
  end
  # rubocop:enable RSpec/BeforeAfterAll

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

  describe "#extract_image_links" do
    it "replaces all instances" do
      line = "a [![button](/button.jpg)](/goes/here) ![button](/button.jpg)"
      new_line, _ = job.extract_image_links(line)
      expect(new_line).to(eq("a [84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0](/goes/here) 84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0"))
    end

    it "ignores text portion" do
      line = "a [![button](/button.jpg)](/goes/here) ![](/button.jpg)"
      new_line, _ = job.extract_image_links(line)
      expect(new_line).to(eq("a [84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0](/goes/here) 84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0"))
    end

    it "replaces all images" do
      line = "a [![button](/button.jpg)](/goes/here) so does [a link](/goes/here) and ![](not/button.jpg)"
      new_line, _ = job.extract_image_links(line)
      expect(new_line).to(eq("a [84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0](/goes/here) so does [a link](/goes/here) and f93298ab159e9e646b6b794806065b68a588343507367003cb4621dbc2c16614"))
    end

    it "returns the original line if no images" do
      line = "there are [no images](/link/here) in this"
      new_line, _ = job.extract_image_links(line)
      expect(line).to(eq(new_line))
    end

    it "returns an empty replacement hash if no images" do
      line = "there are [no images](/link/here) in this"
      _, image_url_hashes = job.extract_image_links(line)
      expect(image_url_hashes.size).to(eq(0))
    end

    it "returns has for reinsertion", :aggregate_failures do
      line = "a [![button](/button.jpg)](/goes/here) so does [a link](/goes/here) and ![](not/button.jpg)"
      _, image_url_hashes = job.extract_image_links(line)
      expect(image_url_hashes["84587aeb699485657198f7a78ad7b356341a90cb3a3dcb275ab19f3ef631f3e0"]).to(
        eq("/button.jpg")
      )
      expect(image_url_hashes["f93298ab159e9e646b6b794806065b68a588343507367003cb4621dbc2c16614"]).to(
        eq("not/button.jpg")
      )
      expect(image_url_hashes.size).to(eq(2))
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
      allow(job).to(receive(:download_image).and_return("archived_image_url"))
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
      line_4 = "this line 4 [link1](https://example.com/foo/foo), ![](archived_image_url) has two & one's an image"

      line_5 = "[line 5](https://example.com/foo/foo), starts & ends with a [link2](https://example.com/boo.jpg)"

      expect(processed_lines[3]).to(eq(line_4))
      expect(processed_lines[4]).to(eq(line_5))
    end

    it "handles images in links" do
      line_6 = "[![](archived_image_url)](https://example.com/thats/a/link)"
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

    it "handles fully qualified urls correctly", :aggregate_failures do
      expect(job.fully_qualify_path(
        "https://sub.example.com/boo.jpg", domain, directory
      )).to(eq("https://sub.example.com/boo.jpg"))
      expect(job.fully_qualify_path(
        "https://sub.example.com/boo", domain, directory
      )).to(eq("https://sub.example.com/boo"))
    end
  end

  describe "#archived_image_name" do
    it "is sha 256 hash + extension" do
      expect(job.archived_image_name(image_url))
        .to(
          eq(local_image_name)
        )
    end
  end

  describe "#download_image" do
    # bookmark_url: "https://example.com/foo/"
    it "creates a folder" do
      FileUtils.rm_r(bookmark_image_dir, force: true) if File.exist?(bookmark_image_dir)
      allow(job).to(
        receive(:url_downloadable?)
          .with(image_url, {include_code: true})
          .and_return(true)
      )
      # don't actually download
      allow(HTTParty).to(receive(:get).and_return(nil))
      job.download_image(bookmark, image_url)
      expect(File.exist?(bookmark_image_path)).to(be(true))
    end

    it "does not have problems with an existing folder" do
      FileUtils.mkdir_p(bookmark_image_dir)
      allow(job).to(
        receive(:url_downloadable?)
          .with(image_url, {include_code: true})
          .and_return(true)
      )
      # don't actually download
      allow(HTTParty).to(receive(:get).and_return(nil))
      job.download_image(bookmark, image_url)
      expect(File.exist?(bookmark_image_path)).to(be(true))
    end

    it "does not attempt to download an image we already have" do
      FileUtils.mkdir_p(bookmark_image_dir)
      FileUtils.touch(bookmark_image_path) unless File.exist?(bookmark_image_path)
      allow(job).to(
        receive(:url_downloadable?)
          .with(image_url, {include_code: true})
          .and_return(true)
      )
      expect(File).not_to(receive(:open))
      job.download_image(bookmark, image_url)
    end

    # it "should return empty string if was tracking pixel"
    it "returns new url if things work" do
      FileUtils.mkdir_p(bookmark_image_dir)
      FileUtils.touch(bookmark_image_path) unless File.exist?(bookmark_image_path)
      allow(job).to(
        receive(:url_downloadable?)
          .with(image_url, {include_code: true})
          .and_return(true)
      )
      expect(job.download_image(bookmark, image_url)).to(eq(local_image_url))
    end

    # rubocop:disable RSpec/UnspecifiedException
    # the exception could be any of many things
    # and the full list of things the OS could
    # throw when trying to write is undocumented
    it "raises an exception if something goes wrong" do
      allow(job).to(
        receive(:record_failed_attempt)
          .and_raise(BackupBrain::Errors::UnarchivableUrl.new("foo"))
      )
      expect {
        job.download_image(
          bookmark,
          "https://bogus_url_that_wont_exist.false/bogus.png"
        )
      }.to(raise_error)
    end
    # rubocop:enable RSpec/UnspecifiedException
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
# rubocop:enable RSpec/MultipleMemoizedHelpers
