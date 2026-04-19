require "rails_helper"

RSpec.describe DomainTriggersController, type: :controller do
  login_user

  after do
    DomainTrigger.destroy_all
  end

  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end

    it "returns alpha.com before zebra.com when ordered by domain" do
      create(:domain_trigger, domain: "zebra.com")
      first = create(:domain_trigger, domain: "alpha.com")
      get :index
      ordered = DomainTrigger.all.order_by(domain: :asc).to_a
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
    let(:trigger) { create(:domain_trigger) }

    it "returns a successful response" do
      get :edit, params: {id: trigger.id}
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    context "with valid params" do
      let(:valid_params) do
        {
          domain_trigger: {
            domain: "example.com",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: "video media"
          }
        }
      end

      it "creates a new DomainTrigger" do
        expect {
          post :create, params: valid_params
        }.to change(DomainTrigger, :count).by(1)
      end

      it "splits tags on spaces" do
        post :create, params: valid_params
        trigger = DomainTrigger.find_by(domain: "example.com")
        expect(trigger.tags).to contain_exactly("video", "media")
      end

      it "redirects to domain_triggers_path" do
        post :create, params: valid_params
        expect(response).to redirect_to(domain_triggers_path)
      end

      it "sets a flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params (missing domain)" do
      let(:invalid_params) do
        {
          domain_trigger: {
            domain: "",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "does not create a DomainTrigger" do
        expect {
          post :create, params: invalid_params
        }.not_to change(DomainTrigger, :count)
      end

      it "renders with unprocessable_entity status" do
        post :create, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH #update" do
    let!(:trigger) { create(:domain_trigger, domain: "old.com") }

    context "with valid params" do
      let(:update_params) do
        {
          id: trigger.id,
          domain_trigger: {
            domain: "new.com",
            mark_as_private: "0",
            mark_as_sensitive: "1",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "updates the DomainTrigger domain" do
        patch :update, params: update_params
        expect(trigger.reload.domain).to eq("new.com")
      end

      it "sets mark_as_sensitive to true" do
        patch :update, params: update_params
        expect(trigger.reload.mark_as_sensitive).to be true
      end

      it "redirects to domain_triggers_path" do
        patch :update, params: update_params
        expect(response).to redirect_to(domain_triggers_path)
      end

      it "sets a flash notice" do
        patch :update, params: update_params
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid params (duplicate domain)" do
      let!(:other_trigger) { create(:domain_trigger, domain: "taken.com") }
      let(:update_params) do
        {
          id: trigger.id,
          domain_trigger: {
            domain: "taken.com",
            mark_as_private: "0",
            mark_as_sensitive: "0",
            mark_to_read: "0",
            tags: ""
          }
        }
      end

      it "does not update the trigger domain" do
        patch :update, params: update_params
        expect(trigger.reload.domain).to eq("old.com")
      end

      it "renders with unprocessable_entity status" do
        patch :update, params: update_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:trigger) { create(:domain_trigger) }

    it "destroys the DomainTrigger" do
      expect {
        delete :destroy, params: {id: trigger.id}
      }.to change(DomainTrigger, :count).by(-1)
    end

    it "redirects to domain_triggers_path" do
      delete :destroy, params: {id: trigger.id}
      expect(response).to redirect_to(domain_triggers_path)
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
