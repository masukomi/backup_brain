require "rails_helper"

RSpec.describe ContentTriggersController, type: :controller do
  login_user

  after do
    ContentTrigger.destroy_all
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "returns Alpha Trigger before Zebra Trigger when ordered by name" do
      create(:content_trigger, name: "Zebra Trigger")
      first = create(:content_trigger, name: "Alpha Trigger")
      get :index
      ordered = ContentTrigger.all.order_by(name: :asc).to_a
      expect(ordered.first.id).to eq(first.id)
    end
  end

  describe "GET #new" do
    it "returns a successful response" do
      get :new
      expect(response).to be_successful
    end
  end

  describe "GET #edit" do
    let(:trigger) { create(:content_trigger) }

    it "returns a successful response" do
      get :edit, params: {id: trigger.id}
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    context "with valid params" do
      let(:valid_params) do
        {
          content_trigger: {
            name: "YouTube Trigger",
            simple_triggers: "youtube, youtu.be",
            case_insensitive: "1",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: "video media"
          }
        }
      end

      it "creates a new ContentTrigger" do
        expect {
          post :create, params: valid_params
        }.to change(ContentTrigger, :count).by(1)
      end

      it "splits simple_triggers on commas" do
        post :create, params: valid_params
        trigger = ContentTrigger.find_by(name: "YouTube Trigger")
        expect(trigger.simple_triggers).to eq(["youtube", "youtu.be"])
      end

      it "splits tags on spaces" do
        post :create, params: valid_params
        trigger = ContentTrigger.find_by(name: "YouTube Trigger")
        expect(trigger.tags).to contain_exactly("video", "media")
      end

      it "redirects to content_triggers_path" do
        post :create, params: valid_params
        expect(response).to redirect_to(content_triggers_path)
      end

      it "sets a flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params (missing name)" do
      let(:invalid_params) do
        {
          content_trigger: {
            name: "",
            simple_triggers: "foo",
            case_insensitive: "1",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "does not create a ContentTrigger" do
        expect {
          post :create, params: invalid_params
        }.not_to change(ContentTrigger, :count)
      end

      it "renders with unprocessable_entity status" do
        post :create, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH #update" do
    let!(:trigger) { create(:content_trigger, name: "Old Name", simple_triggers: ["old"]) }

    context "with valid params" do
      let(:update_params) do
        {
          id: trigger.id,
          content_trigger: {
            name: "New Name",
            simple_triggers: "new, newer",
            case_insensitive: "0",
            mark_as_private: "1",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "updates the ContentTrigger name" do
        patch :update, params: update_params
        expect(trigger.reload.name).to eq("New Name")
      end

      it "updates simple_triggers from comma-separated string" do
        patch :update, params: update_params
        expect(trigger.reload.simple_triggers).to eq(["new", "newer"])
      end

      it "sets mark_as_private to true" do
        patch :update, params: update_params
        expect(trigger.reload.mark_as_private).to be true
      end

      it "sets case_insensitive to false" do
        patch :update, params: update_params
        expect(trigger.reload.case_insensitive).to be false
      end

      it "redirects to content_triggers_path" do
        patch :update, params: update_params
        expect(response).to redirect_to(content_triggers_path)
      end

      it "sets a flash notice" do
        patch :update, params: update_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params (duplicate name)" do
      let!(:other_trigger) { create(:content_trigger, name: "Taken Name") }
      let(:update_params) do
        {
          id: trigger.id,
          content_trigger: {
            name: "Taken Name",
            simple_triggers: "foo",
            case_insensitive: "1",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "does not update the trigger name" do
        patch :update, params: update_params
        expect(trigger.reload.name).to eq("Old Name")
      end

      it "renders with unprocessable_entity status" do
        patch :update, params: update_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:trigger) { create(:content_trigger) }

    it "destroys the ContentTrigger" do
      expect {
        delete :destroy, params: {id: trigger.id}
      }.to change(ContentTrigger, :count).by(-1)
    end

    it "redirects to content_triggers_path" do
      delete :destroy, params: {id: trigger.id}
      expect(response).to redirect_to(content_triggers_path)
    end

    it "responds with see_other status" do
      delete :destroy, params: {id: trigger.id}
      expect(response).to have_http_status(:see_other)
    end

    it "sets a flash notice" do
      delete :destroy, params: {id: trigger.id}
      expect(flash[:notice]).to be_present
    end
  end

  describe "authentication" do
    it "redirects unauthenticated GET #index to sign-in" do
      sign_out :user
      get :index
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
