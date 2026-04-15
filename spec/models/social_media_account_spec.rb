require "rails_helper"

RSpec.describe SocialMediaAccount do
  let(:sma) do
    described_class.new(
      profile_url: "https://mastodon.social/@alice",
      service: "mastodon",
      type: "unknown"
    )
  end
  let(:archive_folder) { "archives/social_media_accounts/#{sma._id}" }

  # Shared setup: stub remote_account_data so tests don't hit the network
  before do
    allow(sma).to(receive(:archive_folder_path_for_doc).with(sma).and_return(archive_folder))
  end

  describe "#default_avatar_image_path" do
    context "when the service is mastodon" do
      # rubocop:disable RSpec/ContextWording
      context "and remote_account_data returns an avatar URL with an extension" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(
            {"avatar" => "https://cdn.mastodon.social/accounts/avatars/001/original/alice.jpg",
             "header" => "https://cdn.mastodon.social/accounts/headers/001/original/banner.png"}
          ))
        end

        it "returns a path under the archive folder named avatar with the correct extension" do
          expect(sma.default_avatar_image_path).to(eq("#{archive_folder}/avatar.jpg"))
        end
      end

      context "and the avatar URL has a query string" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(
            {"avatar" => "https://cdn.mastodon.social/accounts/avatars/001/original/alice.png?v=42",
             "header" => nil}
          ))
        end

        it "strips the query string and uses only the extension" do
          expect(sma.default_avatar_image_path).to(eq("#{archive_folder}/avatar.png"))
        end
      end

      context "and remote_account_data returns a nil avatar" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return({"avatar" => nil, "header" => nil}))
        end

        it "returns nil" do
          expect(sma.default_avatar_image_path).to(be_nil)
        end
      end

      context "and remote_account_data returns a URL with no extension" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(
            {"avatar" => "https://cdn.mastodon.social/accounts/avatars/001/original/alice",
             "header" => nil}
          ))
        end

        it "returns nil" do
          expect(sma.default_avatar_image_path).to(be_nil)
        end
      end

      context "and remote_account_data is nil" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(nil))
        end

        it "returns nil" do
          expect(sma.default_avatar_image_path).to(be_nil)
        end
      end
      # rubocop:enable RSpec/ContextWording
    end

    context "when the service maps to mastodon (e.g. gotosocial)" do
      let(:sma) do
        described_class.new(
          profile_url: "https://gotosocial.example/@alice",
          service: "gotosocial",
          type: "unknown"
        )
      end

      before do
        allow(sma).to(receive(:archive_folder_path_for_doc).with(sma).and_return(archive_folder))
        allow(sma).to(receive(:remote_account_data).and_return(
          {"avatar" => "https://gotosocial.example/media/alice.webp", "header" => nil}
        ))
      end

      it "returns a path using the correct extension" do
        expect(sma.default_avatar_image_path).to(eq("#{archive_folder}/avatar.webp"))
      end
    end

    context "when the service is unsupported (e.g. misskey)" do
      let(:sma) do
        described_class.new(
          profile_url: "https://misskey.io/@alice",
          service: "misskey",
          type: "unknown"
        )
      end

      before do
        allow(sma).to(receive(:archive_folder_path_for_doc).with(sma).and_return(archive_folder))
      end

      it "returns nil" do
        expect(sma.default_avatar_image_path).to(be_nil)
      end
    end
  end

  describe "#default_header_image_path" do
    context "when the service is mastodon" do
      # rubocop:disable RSpec/ContextWording
      context "and remote_account_data returns a header URL with an extension" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(
            {"avatar" => "https://cdn.mastodon.social/accounts/avatars/001/original/alice.jpg",
             "header" => "https://cdn.mastodon.social/accounts/headers/001/original/banner.png"}
          ))
        end

        it "returns a path under the archive folder named header with the correct extension" do
          expect(sma.default_header_image_path).to(eq("#{archive_folder}/header.png"))
        end
      end

      context "and the header URL has a query string" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(
            {"avatar" => nil,
             "header" => "https://cdn.mastodon.social/accounts/headers/001/original/banner.gif?v=7"}
          ))
        end

        it "strips the query string and uses only the extension" do
          expect(sma.default_header_image_path).to(eq("#{archive_folder}/header.gif"))
        end
      end

      context "and remote_account_data returns a nil header" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return({"avatar" => nil, "header" => nil}))
        end

        it "returns nil" do
          expect(sma.default_header_image_path).to(be_nil)
        end
      end

      context "and remote_account_data is nil" do
        before do
          allow(sma).to(receive(:remote_account_data).and_return(nil))
        end

        it "returns nil" do
          expect(sma.default_header_image_path).to(be_nil)
        end
      end
      # rubocop:enable RSpec/ContextWording
    end

    context "when the service is unsupported" do
      let(:sma) do
        described_class.new(
          profile_url: "https://misskey.io/@alice",
          service: "misskey",
          type: "unknown"
        )
      end

      before do
        allow(sma).to(receive(:archive_folder_path_for_doc).with(sma).and_return(archive_folder))
      end

      it "returns nil" do
        expect(sma.default_header_image_path).to(be_nil)
      end
    end
  end
end
