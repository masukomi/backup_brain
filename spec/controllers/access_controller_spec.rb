require "rails_helper"

RSpec.describe AccessController, type: :controller do
  render_views
  login_user

  after { ApiKey.destroy_all }

  describe "POST #create_api_key" do
    context "with valid params" do
      before do
        post :create_api_key, params: {api_key: {name: "agent", permissions: ["read:notes"]}}
      end

      it "creates the key" do
        expect(ApiKey.where(name: "agent").count).to eq(1)
      end

      # Turbo ignores a 200 response to a form post, so the create must redirect.
      it "redirects to the page that shows the new key" do
        expect(response).to redirect_to(show_api_key_path(ApiKey.where(name: "agent").first))
      end
    end

    it "re-renders the form on invalid params" do
      post :create_api_key, params: {api_key: {name: ""}}
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET #show_api_key" do
    let(:api_key) { create(:api_key) }

    before { get :show_api_key, params: {id: api_key.id} }

    it "is successful" do
      expect(response).to be_successful
    end

    it "shows the key value" do
      expect(response.body).to include(api_key.key)
    end

    it "offers to copy the key" do
      expect(response.body).to include(I18n.t("access.api_keys.copy_button"))
    end
  end
end
