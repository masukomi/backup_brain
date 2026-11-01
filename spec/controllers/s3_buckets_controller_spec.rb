require "rails_helper"

RSpec.describe S3BucketsController, type: :controller do
  render_views # the templates and the secret-hiding form are part of what's under test
  login_user

  after do
    S3Bucket.destroy_all
    BackupBrain::S3Storage.reload!
  end

  def bucket_attributes(overrides = {})
    {
      nickname: "main",
      name: "bb-archives",
      endpoint: "http://localhost:9000",
      region: "us-east-1",
      access_key_id: "key-id",
      secret_access_key: "key-secret",
      key_prefix: "",
      presigned_url_expiry: "3600",
      path_style_urls: "1",
      enabled: "1",
      primary: "0"
    }.merge(overrides)
  end

  describe "GET #index" do
    it "returns a successful response with no buckets" do
      get :index
      expect(response).to be_successful
    end

    it "returns a successful response with buckets" do
      create(:s3_bucket)
      get :index
      expect(response).to be_successful
    end

    it "lists the primary bucket first" do
      mirror = create(:s3_bucket, nickname: "aaa mirror")
      primary = create(:s3_bucket, nickname: "zzz main", primary: true)
      get :index
      expect(response.body.index("s3_bucket_#{primary.id}")).to be < response.body.index("s3_bucket_#{mirror.id}")
    end
  end

  describe "GET #new" do
    it "returns a successful response" do
      get :new
      expect(response).to be_successful
    end
  end

  describe "GET #edit" do
    let(:bucket) { create(:s3_bucket) }

    it "returns a successful response" do
      get :edit, params: {id: bucket.id}
      expect(response).to be_successful
    end

    it "does not put the secret in the page" do
      get :edit, params: {id: bucket.id}
      expect(response.body).not_to include(bucket.secret_access_key)
    end
  end

  describe "POST #create" do
    context "with valid params" do
      it "creates a new S3Bucket" do
        expect {
          post :create, params: {s3_bucket: bucket_attributes}
        }.to change(S3Bucket, :count).by(1)
      end

      it "stores the credentials" do
        post :create, params: {s3_bucket: bucket_attributes}
        expect(S3Bucket.first.secret_access_key).to eq("key-secret")
      end

      it "makes the first enabled bucket the primary" do
        post :create, params: {s3_bucket: bucket_attributes}
        expect(S3Bucket.first).to be_primary
      end

      it "redirects to the list" do
        post :create, params: {s3_bucket: bucket_attributes}
        expect(response).to redirect_to(s3_buckets_path)
      end

      it "sets a flash notice" do
        post :create, params: {s3_bucket: bucket_attributes}
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params (missing bucket name)" do
      it "does not create an S3Bucket" do
        expect {
          post :create, params: {s3_bucket: bucket_attributes(name: "")}
        }.not_to change(S3Bucket, :count)
      end

      it "renders with unprocessable_entity status" do
        post :create, params: {s3_bucket: bucket_attributes(name: "")}
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "with a disabled bucket marked primary" do
      it "renders with unprocessable_entity status" do
        post :create, params: {s3_bucket: bucket_attributes(enabled: "0", primary: "1")}
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH #update" do
    let!(:bucket) { create(:s3_bucket, nickname: "old", secret_access_key: "old-secret") }

    it "updates the bucket" do
      patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes(nickname: "new")}
      expect(bucket.reload.nickname).to eq("new")
    end

    it "keeps the stored secret when the field is left blank" do
      patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes(secret_access_key: "")}
      expect(bucket.reload.secret_access_key).to eq("old-secret")
    end

    it "replaces the secret when one is given" do
      patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes(secret_access_key: "new-secret")}
      expect(bucket.reload.secret_access_key).to eq("new-secret")
    end

    it "redirects to the list" do
      patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes}
      expect(response).to redirect_to(s3_buckets_path)
    end

    it "sets a flash notice" do
      patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes}
      expect(flash[:notice]).to be_present
    end

    context "when another bucket is made primary" do
      let!(:other) { create(:s3_bucket, nickname: "other") }

      it "demotes the old primary" do
        patch :update, params: {id: other.id, s3_bucket: bucket_attributes(nickname: "other", primary: "1")}
        expect(bucket.reload).not_to be_primary
      end
    end

    context "with invalid params (duplicate nickname)" do
      before { create(:s3_bucket, nickname: "taken") }

      it "does not update the bucket" do
        patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes(nickname: "taken")}
        expect(bucket.reload.nickname).to eq("old")
      end

      it "renders with unprocessable_entity status" do
        patch :update, params: {id: bucket.id, s3_bucket: bucket_attributes(nickname: "taken")}
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:bucket) { create(:s3_bucket) }

    it "destroys the S3Bucket" do
      expect {
        delete :destroy, params: {id: bucket.id}
      }.to change(S3Bucket, :count).by(-1)
    end

    it "redirects to the list" do
      delete :destroy, params: {id: bucket.id}
      expect(response).to redirect_to(s3_buckets_path)
    end

    it "responds with see_other status" do
      delete :destroy, params: {id: bucket.id}
      expect(response).to have_http_status(:see_other)
    end

    it "sets a flash notice" do
      delete :destroy, params: {id: bucket.id}
      expect(flash[:notice]).to be_present
    end
  end

  describe "authentication" do
    it "redirects unauthenticated GET #index to sign-in" do
      sign_out :user
      get :index
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects unauthenticated POST #create to sign-in" do
      sign_out :user
      post :create, params: {s3_bucket: bucket_attributes}
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
