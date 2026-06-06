require "rails_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe FetchMastodonBookmarksJob do
  let(:job) { described_class.new }
  let(:bookmark) { Bookmark.new(url: "https://mastodon.social/@user/123") }
  let(:access_token) { "test_token_abc" }
  let(:media_url) { "https://cdn.masto.host/files/image.png" }

  # rubocop:disable RSpec/VerifiedDoubles
  def stub_http_response(code:, body: "image_bytes", headers: {})
    double("HTTParty::Response",
      success?: code < 400,
      code: code,
      body: body,
      headers: headers)
  end
  # rubocop:enable RSpec/VerifiedDoubles
  # Avoid real filesystem operations in fetch_url tests
  before do
    allow(FileUtils).to(receive(:mkdir_p))
    allow(File).to(receive(:binwrite))
    allow(File).to(receive(:exist?)).and_return(true)
  end

  describe "#fetch_url" do
    context "when the request succeeds" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 200)))
      end

      # rubocop:disable RSpec/StubbedMock
      it "sends Authorization header by default" do
        expect(HTTParty).to(receive(:get).with(
          media_url,
          hash_including(headers: {"Authorization" => "Bearer #{access_token}"})
        ).and_return(stub_http_response(code: 200)))
        job.send(:fetch_url, media_url, bookmark, access_token)
      end

      it "omits Authorization header when with_token: false" do
        expect(HTTParty).to(receive(:get).with(
          media_url,
          hash_including(headers: {})
        ).and_return(stub_http_response(code: 200)))
        job.send(:fetch_url, media_url, bookmark, access_token, with_token: false)
      end
      # rubocop:enable RSpec/StubbedMock

      it "returns a hash with :url key on success", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result).to(have_key(:url))
        expect(result).not_to(have_key(:error))
      end

      it "returns a local web path as the url" do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:url]).to(match(%r{/archives/bookmarks/}))
      end
    end

    context "when the server returns 429" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 429)))
      end

      it "returns error with retry: true", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:error]).to(be_present)
        expect(result[:retry]).to(be(true))
      end

      it "does not set unauth_retry" do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:unauth_retry]).to(be_nil)
      end
    end

    context "when the server returns 403 with token" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 403)))
      end

      it "returns error with unauth_retry: true", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:error]).to(be_present)
        expect(result[:unauth_retry]).to(be(true))
      end

      it "does not set retry: true" do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:retry]).to(be_nil)
      end
    end

    context "when the server returns 403 without token" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 403)))
      end

      it "returns plain error without unauth_retry", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token, with_token: false)
        expect(result[:error]).to(be_present)
        expect(result[:unauth_retry]).to(be_nil)
        expect(result[:retry]).to(be_nil)
      end
    end

    context "when the server returns 500" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 500)))
      end

      it "returns plain error without retry flags", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:error]).to(be_present)
        expect(result[:retry]).to(be_nil)
        expect(result[:unauth_retry]).to(be_nil)
      end
    end

    context "when an exception is raised" do
      before do
        allow(HTTParty).to(receive(:get).and_raise(Net::OpenTimeout, "connection timed out"))
      end

      it "returns an error hash", :aggregate_failures do
        result = job.send(:fetch_url, media_url, bookmark, access_token)
        expect(result[:error]).to(be_present)
        expect(result).not_to(have_key(:url))
      end
    end
  end

  describe "#download_media_attachment" do
    let(:local_url) { "https://mastodon.social/media/local.png" }
    let(:remote_url) { "https://cdn.example.com/media/remote.png" }
    let(:success_result) { {url: "/archives/bookmarks/123/abc.png"} }
    let(:non_retry_error) { {error: "404 not found"} }
    let(:retry_error) { {error: "429 rate limit", retry: true} }
    let(:unauth_retry_result) { {error: "403 forbidden", unauth_retry: true} }

    # Suppress logger noise in these tests
    before do
      allow(Rails.logger).to(receive(:warn))
      allow(Rails.logger).to(receive(:info))
    end

    context "when remote_url succeeds" do
      it "returns the result without trying local_url", :aggregate_failures do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(success_result))
        expect(job).not_to(receive(:fetch_url).with(local_url, anything, anything))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(success_result))
      end

      # rubocop:disable RSpec/StubbedMock
      it "sends remote_url without a token" do
        expect(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(success_result))

        job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
      end
      # rubocop:enable RSpec/StubbedMock
    end

    context "when remote_url fails and local_url succeeds" do
      it "falls back to local_url with token" do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token)
          .and_return(success_result))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(success_result))
      end
    end

    context "when local_url returns 403 with token (unauth_retry)" do
      before do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token)
          .and_return(unauth_retry_result))
      end

      it "retries local_url without token and returns success" do
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token, with_token: false)
          .and_return(success_result))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(success_result))
      end

      it "logs the unauthenticated retry at info level" do
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token, with_token: false)
          .and_return(success_result))
        expect(Rails.logger).to(receive(:info).with(/403.*retrying without token/))

        job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
      end

      it "returns the error when the unauthenticated retry also fails" do
        final_error = {error: "still denied"}
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token, with_token: false)
          .and_return(final_error))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(final_error))
      end
    end

    context "when local_url 429s then succeeds on retry" do
      it "sleeps and retries, returning success" do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token)
          .and_return(retry_error, success_result))
        allow(job).to(receive(:sleep))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(success_result))
      end
    end

    context "when local_url 429s on every attempt" do
      it "gives up and returns a gave-up error" do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))
        allow(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token)
          .and_return(retry_error))
        allow(job).to(receive(:sleep))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result[:error]).to(match(/gave up/))
      end
    end

    context "when local_url has a non-retriable error" do
      it "returns the error without exhausting all attempts", :aggregate_failures do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))
        expect(job).to(receive(:fetch_url)
          .with(local_url, bookmark, access_token)
          .once
          .and_return(non_retry_error))

        result = job.send(:download_media_attachment, local_url, remote_url, bookmark, access_token)
        expect(result).to(eq(non_retry_error))
      end
    end

    context "when remote_url fails and local_url is blank" do
      it "returns an error immediately" do
        allow(job).to(receive(:fetch_url)
          .with(remote_url, bookmark, access_token, with_token: false)
          .and_return(non_retry_error))

        result = job.send(:download_media_attachment, nil, remote_url, bookmark, access_token)
        expect(result[:error]).to(be_present)
      end
    end

    context "when both remote_url and local_url are absent" do
      it "returns an error" do
        result = job.send(:download_media_attachment, nil, nil, bookmark, access_token)
        expect(result[:error]).to(be_present)
      end
    end
  end

  describe "#parse_next_link" do
    it "extracts the next URL from a Link header" do
      header = '<https://mastodon.social/api/v1/bookmarks?max_id=123>; rel="next", ' \
               '<https://mastodon.social/api/v1/bookmarks?min_id=456>; rel="prev"'
      expect(job.send(:parse_next_link, header)).to(
        eq("https://mastodon.social/api/v1/bookmarks?max_id=123")
      )
    end

    it "returns nil when header is nil" do
      expect(job.send(:parse_next_link, nil)).to(be_nil)
    end

    it "returns nil when header is empty" do
      expect(job.send(:parse_next_link, "")).to(be_nil)
    end

    it "returns nil when there is no next rel" do
      header = '<https://mastodon.social/api/v1/bookmarks?min_id=456>; rel="prev"'
      expect(job.send(:parse_next_link, header)).to(be_nil)
    end
  end

  describe "#fetch_bookmarks_page" do
    let(:base_url) { "https://mastodon.social" }
    let(:statuses) { [{"url" => "https://mastodon.social/@user/1", "content" => "<p>hello</p>"}] }
    let(:link_header) { '<https://mastodon.social/api/v1/bookmarks?max_id=99>; rel="next"' }

    context "when the request succeeds" do
      before do
        allow(HTTParty).to(receive(:get).and_return(
          stub_http_response(code: 200, body: statuses.to_json, headers: {"link" => link_header})
        ))
      end

      it "returns the parsed statuses" do
        result_statuses, = job.send(:fetch_bookmarks_page, base_url, access_token)
        expect(result_statuses).to(eq(statuses))
      end

      it "returns the next_url from the Link header" do
        _, next_url = job.send(:fetch_bookmarks_page, base_url, access_token)
        expect(next_url).to(eq("https://mastodon.social/api/v1/bookmarks?max_id=99"))
      end

      # rubocop:disable RSpec/StubbedMock
      it "sends Authorization header" do
        expect(HTTParty).to(receive(:get).with(
          "#{base_url}/api/v1/bookmarks",
          hash_including(headers: {"Authorization" => "Bearer #{access_token}"})
        ).and_return(stub_http_response(code: 200, body: [].to_json, headers: {})))

        job.send(:fetch_bookmarks_page, base_url, access_token)
      end
      # rubocop:enable RSpec/StubbedMock
    end

    context "when a custom page_url is provided" do
      let(:page_url) { "https://mastodon.social/api/v1/bookmarks?max_id=999" }

      # rubocop:disable RSpec/StubbedMock
      it "uses the provided url instead of the default bookmarks endpoint" do
        expect(HTTParty).to(receive(:get).with(page_url, anything).and_return(
          stub_http_response(code: 200, body: [].to_json, headers: {})
        ))
        job.send(:fetch_bookmarks_page, base_url, access_token, page_url)
      end
      # rubocop:enable RSpec/StubbedMock
    end

    context "when the request returns a non-2xx status" do
      before do
        allow(HTTParty).to(receive(:get).and_return(stub_http_response(code: 401)))
      end

      it "returns empty statuses" do
        statuses, = job.send(:fetch_bookmarks_page, base_url, access_token)
        expect(statuses).to(eq([]))
      end

      it "returns nil for next_url" do
        _, next_url = job.send(:fetch_bookmarks_page, base_url, access_token)
        expect(next_url).to(be_nil)
      end
    end

    context "when an exception is raised" do
      before do
        allow(HTTParty).to(receive(:get).and_raise(Net::OpenTimeout, "timed out"))
        allow(Rails.logger).to(receive(:error))
      end

      it "returns empty statuses and nil next_url", :aggregate_failures do
        statuses, next_url = job.send(:fetch_bookmarks_page, base_url, access_token)
        expect(statuses).to(eq([]))
        expect(next_url).to(be_nil)
      end
    end
  end

  describe "#build_title" do
    let(:status) do
      {
        "created_at" => "2024-01-15T10:30:00.000Z",
        "account"    => {"display_name" => "Alice", "acct" => "alice@mastodon.social"}
      }
    end

    it "uses display_name when present" do
      title = job.send(:build_title, "", status)
      expect(title).to(include("Alice"))
    end

    it "falls back to acct prefixed with @ when display_name is blank" do
      status["account"]["display_name"] = ""
      title = job.send(:build_title, "", status)
      expect(title).to(include("@alice@mastodon.social"))
    end

    it "includes a formatted timestamp" do
      title = job.send(:build_title, "", status)
      expect(title).to(include("2024/01/15 10:30"))
    end
  end

  describe "#embed_youtube_videos" do
    let(:archive) { Archive.new(mime_type: "text/markdown", string_data: content) }

    context "when the archive contains a youtube.com/watch URL" do
      let(:content) { "check out [this video](https://www.youtube.com/watch?v=dQw4w9WgXcQ)" }

      it "appends an iframe for the video", :aggregate_failures do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to(include("<iframe"))
        expect(archive.string_data).to(include("youtube.com/embed/dQw4w9WgXcQ"))
      end

      it "preserves the original content" do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to(include(content.strip))
      end
    end

    context "when the archive contains a youtu.be URL" do
      let(:content) { "https://youtu.be/dQw4w9WgXcQ" }

      it "appends an iframe for the video" do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to(include("youtube.com/embed/dQw4w9WgXcQ"))
      end
    end

    context "when the same video is linked multiple times" do
      let(:content) { "https://youtu.be/dQw4w9WgXcQ and https://www.youtube.com/watch?v=dQw4w9WgXcQ" }

      it "only appends one iframe" do
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data.scan("youtube.com/embed/dQw4w9WgXcQ").length).to(eq(1))
      end
    end

    context "when the archive has no YouTube URLs" do
      let(:content) { "just a [normal link](https://example.com)" }

      it "does not modify the archive" do
        original = content.dup
        job.send(:embed_youtube_videos, archive)
        expect(archive.string_data).to(eq(original))
      end
    end
  end

  describe "#find_or_create_sma_for" do
    let(:profile_url) { "https://mastodon.social/@alice" }
    let(:account_data) do
      {
        "url"    => profile_url,
        "acct"   => "alice@mastodon.social",
        "avatar" => "https://cdn.mastodon.social/avatar.jpg",
        "header" => "https://cdn.mastodon.social/header.jpg"
      }
    end

    before do
      allow(Rails.logger).to(receive(:error))
    end

    context "when profile_url is blank" do
      it "returns nil" do
        expect(job.send(:find_or_create_sma_for, account_data.merge("url" => ""))).to(be_nil)
      end
    end

    context "when a SocialMediaAccount already exists for the profile_url" do
      let(:existing_sma) { instance_double(SocialMediaAccount) }

      before do
        # rubocop:disable RSpec/VerifiedDoubles
        allow(SocialMediaAccount).to(receive(:where).with(profile_url: profile_url).and_return(double(first: existing_sma)))
        # rubocop:enable RSpec/VerifiedDoubles
      end

      it "returns the existing SMA" do
        expect(job.send(:find_or_create_sma_for, account_data)).to(eq(existing_sma))
      end

      it "does not enqueue ArchiveSocialMediaAccountJob" do
        expect(ArchiveSocialMediaAccountJob).not_to(receive(:perform_later))
        job.send(:find_or_create_sma_for, account_data)
      end
    end

    context "when no SocialMediaAccount exists for the profile_url" do
      # rubocop:disable RSpec/VerifiedDoubles
      let(:sma_id) { BSON::ObjectId.new }
      let(:new_sma) { double("SocialMediaAccount", id: sma_id) }
      # rubocop:enable RSpec/VerifiedDoubles

      before do
        allow(SocialMediaAccount).to(receive(:find_by).with(profile_url: profile_url).and_return(nil))
        allow(SocialMediaAccount).to(receive(:new).and_return(new_sma))
        allow(new_sma).to(receive(:suppress_auto_archive_job!))
        allow(ArchiveSocialMediaAccountJob).to(receive(:perform_later))
      end

      context "when the new SMA saves successfully" do
        before { allow(new_sma).to(receive(:save).and_return(true)) }

        it "returns the new SMA" do
          expect(job.send(:find_or_create_sma_for, account_data)).to(eq(new_sma))
        end

        it "calls suppress_auto_archive_job! before saving", :aggregate_failures do
          expect(new_sma).to(receive(:suppress_auto_archive_job!).ordered)
          expect(new_sma).to(receive(:save).ordered.and_return(true))
          job.send(:find_or_create_sma_for, account_data)
        end

        it "enqueues ArchiveSocialMediaAccountJob with the known avatar and header URLs" do
          expect(ArchiveSocialMediaAccountJob).to(receive(:perform_later).with(
            hash_including(
              avatar_url: account_data["avatar"],
              header_url: account_data["header"]
            )
          ))
          job.send(:find_or_create_sma_for, account_data)
        end
      end

      context "when the new SMA fails to save" do
        before { allow(new_sma).to(receive(:save).and_return(false)) }

        it "returns the unsaved SMA" do
          expect(job.send(:find_or_create_sma_for, account_data)).to(eq(new_sma))
        end

        it "does not enqueue ArchiveSocialMediaAccountJob" do
          expect(ArchiveSocialMediaAccountJob).not_to(receive(:perform_later))
          job.send(:find_or_create_sma_for, account_data)
        end
      end
    end

    context "when an exception is raised" do
      before do
        allow(SocialMediaAccount).to(receive(:find_by).and_raise(StandardError, "db error"))
      end

      it "logs the error and returns nil", :aggregate_failures do
        expect(Rails.logger).to(receive(:error).with(/could not find\/create SMA/))
        expect(job.send(:find_or_create_sma_for, account_data)).to(be_nil)
      end
    end
  end

  describe "#manual_perform" do
    # rubocop:disable RSpec/VerifiedDoubles
    let(:mastodon_type_id)  { BSON::ObjectId.new }
    let(:gotosocial_type_id) { BSON::ObjectId.new }
    let(:no_types)          { double("Criteria", count: 0) }
    let(:mastodon_only)     { double("Criteria", count: 1) }
    let(:gotosocial_only)   { double("Criteria", count: 1) }
    let(:both_types)        { double("Criteria", count: 2) }
    let(:user)              { double("User") }
    let(:mastodon_site)     { double("OauthSite", access_token: "masto_token", base_url: "https://mastodon.social") }
    let(:gotosocial_site)   { double("OauthSite", access_token: "gts_token",   base_url: "https://gts.example.com") }
    let(:site_no_token)     { double("OauthSite", access_token: nil,           base_url: "https://no-token.example.com") }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(job).to receive(:reschedule).and_return(true)
      allow(job).to receive(:sync_bookmarks_from)
      allow(User).to receive(:first).and_return(user)
      allow(mastodon_only).to receive(:pluck).with(:_id).and_return([mastodon_type_id])
      allow(gotosocial_only).to receive(:pluck).with(:_id).and_return([gotosocial_type_id])
      allow(both_types).to receive(:pluck).with(:_id).and_return([mastodon_type_id, gotosocial_type_id])
    end

    context "when no mastodon or gotosocial OauthSiteType is seeded" do
      before do
        allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(no_types))
      end

      it "logs a warning mentioning both types" do
        expect(Rails.logger).to(receive(:warn).with(/no mastodon or gotosocial/))
        job.manual_perform
      end

      it "reschedules when reschedulable" do
        expect(job).to(receive(:reschedule))
        job.manual_perform(true)
      end

      it "returns true when not reschedulable" do
        expect(job.manual_perform(false)).to(be(true))
      end
    end

    context "when OauthSiteTypes exist but no User is present" do
      before do
        allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(both_types))
        allow(User).to(receive(:first).and_return(nil))
      end

      it "logs a warning and does not sync", :aggregate_failures do
        expect(Rails.logger).to(receive(:warn).with(/no user found/))
        expect(job).not_to(receive(:sync_bookmarks_from))
        job.manual_perform(false)
      end
    end

    context "when types and a user exist" do
      context "with only a mastodon OauthSite" do
        before do
          allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(mastodon_only))
          # rubocop:disable RSpec/VerifiedDoubles
          allow(OauthSite).to(receive(:includes).with(:oauth_site_type).and_return(double(in: [mastodon_site])))
          # rubocop:enable RSpec/VerifiedDoubles
        end

        it "syncs bookmarks from the mastodon site" do
          expect(job).to(receive(:sync_bookmarks_from).with(mastodon_site, user, anything))
          job.manual_perform(false)
        end
      end

      context "with only a gotosocial OauthSite" do
        before do
          allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(gotosocial_only))
          # rubocop:disable RSpec/VerifiedDoubles
          allow(OauthSite).to(receive(:includes).with(:oauth_site_type).and_return(double(in: [gotosocial_site])))
          # rubocop:enable RSpec/VerifiedDoubles
        end

        it "syncs bookmarks from the gotosocial site" do
          expect(job).to(receive(:sync_bookmarks_from).with(gotosocial_site, user, anything))
          job.manual_perform(false)
        end
      end

      context "with both mastodon and gotosocial OauthSites" do
        before do
          allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(both_types))
          # rubocop:disable RSpec/VerifiedDoubles
          allow(OauthSite).to(receive(:includes).with(:oauth_site_type).and_return(double(in: [mastodon_site, gotosocial_site])))
          # rubocop:enable RSpec/VerifiedDoubles
        end

        it "syncs bookmarks from both sites", :aggregate_failures do
          expect(job).to(receive(:sync_bookmarks_from).with(mastodon_site, user, anything))
          expect(job).to(receive(:sync_bookmarks_from).with(gotosocial_site, user, anything))
          job.manual_perform(false)
        end
      end

      context "when an OauthSite has a blank access_token" do
        before do
          allow(OauthSiteType).to(receive(:in).with(slug: %w[mastodon gotosocial]).and_return(both_types))
          # rubocop:disable RSpec/VerifiedDoubles
          allow(OauthSite).to(receive(:includes).with(:oauth_site_type).and_return(double(in: [site_no_token])))
          # rubocop:enable RSpec/VerifiedDoubles
        end

        it "skips that site without syncing" do
          expect(job).not_to(receive(:sync_bookmarks_from))
          job.manual_perform(false)
        end
      end
    end
  end

  describe "#truncate_markdown" do
    it "returns text unchanged when at or under the limit" do
      text = "short text"
      expect(job.send(:truncate_markdown, text, 100)).to(eq(text))
    end

    it "truncates plain text at the first whitespace after the limit" do
      text = "a" * 10 + " extra words"
      result = job.send(:truncate_markdown, text, 10)
      expect(result).to(eq("a" * 10))
    end

    it "does not count image URL bytes toward the limit" do
      visible = "x" * 499
      image = "![alt](https://example.com/huge-image-url.png)"
      text = visible + image + " overflow"
      # 499 visible chars + image (not counted) = should include the image
      result = job.send(:truncate_markdown, text, 500)
      expect(result).to(include(image))
    end

    it "counts only link text, not the URL, for inline links" do
      # link text = "hi" (2 chars); the (url) part should not count
      link = "[hi](https://example.com/very/long/url)"
      filler = " " + "x" * 10
      text = link + filler
      result = job.send(:truncate_markdown, text, 5)
      expect(result).to(include("[hi]"))
    end
  end

  describe "#create_bookmark_from_status" do
    let(:user) { User.first || create(:user) }
    let(:oauth_site_type) do
      OauthSiteType.find_or_create_by!(slug: "mastodon") do |t|
        t.name = "Mastodon"
        t.registration_strategy = "mastodon_v1_apps"
        t.authorization_path = "/oauth/authorize"
        t.token_path = "/oauth/token"
      end
    end
    let(:oauth_site) do
      OauthSite.where(base_url: "https://mastodon.social").first || OauthSite.create!(
        base_url: "https://mastodon.social",
        registered_url: "https://localhost:3334",
        oauth_site_type: oauth_site_type,
        access_token: "token123"
      )
    end
    let(:status_id) { "987#{rand(10**6)}" }
    let(:status) do
      {
        "id"                => status_id,
        "url"               => "https://mastodon.social/@test/#{status_id}",
        "content"           => "<p>Hello world</p>",
        "created_at"        => "2024-01-15T10:30:00.000Z",
        "sensitive"         => false,
        "account"           => {
          "url"          => "https://mastodon.social/@test",
          "acct"         => "test",
          "display_name" => "Test User",
          "avatar"       => "https://mastodon.social/avatar.png",
          "header"       => "https://mastodon.social/header.png"
        },
        "media_attachments" => []
      }
    end

    before do
      allow(Setting).to(receive(:get_value_of_key).with("enable_archiving").and_return(true))
      allow(Setting).to(receive(:get_value_of_key).with("archival_requests_timeout").and_return(10))
    end

    it "creates a bookmark with an api_archive_source", :aggregate_failures do
      allow(job).to(receive(:find_or_create_sma_for).and_return(nil))
      expect {
        job.send(:create_bookmark_from_status, status, user, oauth_site)
      }.to change(Bookmark, :count).by(1)

      created_bookmark = Bookmark.last
      expect(created_bookmark.api_archive_source).to be_present
      expect(created_bookmark.api_archive_source.remote_id).to eq(status_id)
      expect(created_bookmark.api_archive_source.service).to eq("mastodon")
      expect(created_bookmark.api_archive_source.oauth_site).to eq(oauth_site)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
