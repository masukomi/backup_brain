require "rails_helper"

RSpec.describe ArchivesController do
  login_user

  let(:bookmark) { Bookmark.create!(url: "https://example.com/show", title: "Show", user: User.first) }
  let(:storage) { BackupBrain::S3Storage.instance }
  let(:s3_enabled) { false }

  def folder
    Rails.root.join("archives", "bookmarks", bookmark._id.to_s)
  end

  def show_params
    {object_type: "bookmarks", id: bookmark._id.to_s, filename: "deadbeef", format: "mp3"}
  end

  # rubocop:disable RSpec/AnyInstance
  before do
    allow_any_instance_of(Bookmark).to receive(:add_to_search)
    allow_any_instance_of(Bookmark).to receive(:update_in_search)
    allow_any_instance_of(Bookmark).to receive(:remove_from_search)
    allow_any_instance_of(Bookmark).to receive(:generate_archive)
    allow(BackupBrain::S3Storage).to receive(:enabled?).and_return(s3_enabled)
  end
  # rubocop:enable RSpec/AnyInstance

  after do
    FileUtils.rm_rf(folder)
    Bookmark.destroy_all
    Tag.destroy_all
  end

  describe "GET show" do
    context "when the file is on disk" do
      before do
        FileUtils.mkdir_p(folder)
        File.write(folder.join("deadbeef.mp3"), "audio bytes")
        get :show, params: show_params
      end

      it "serves it" do
        expect(response).to have_http_status(:ok)
      end
    end

    context "when the file is missing and S3 storage is off" do
      before { get :show, params: show_params }

      it "is not found" do
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the file is missing and S3 holds it" do
      let(:s3_enabled) { true }

      before do
        key = "bookmarks/#{bookmark._id}/deadbeef.mp3"
        allow(storage).to receive(:exists?).with(key).and_return(true)
        allow(storage).to receive(:presigned_url).with(key).and_return("https://s3.example.test/signed")
        get :show, params: show_params
      end

      it "redirects to a presigned URL" do
        expect(response).to redirect_to("https://s3.example.test/signed")
      end
    end

    context "when the file is missing locally and in S3" do
      let(:s3_enabled) { true }

      before do
        allow(storage).to receive(:exists?).and_return(false)
        get :show, params: show_params
      end

      it "is not found" do
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
