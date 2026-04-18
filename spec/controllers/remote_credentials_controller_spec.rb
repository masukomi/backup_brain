require "rails_helper"

RSpec.describe RemoteCredentialsController, type: :controller do
  login_user

  let(:local_url) { "http://brain.test:3334" }
  let(:callback_url) { "#{local_url}/remote_authorizations/callback" }

  # Stub ENV so local_url / callback_url work without a real .env
  # Stub Setting so IndieAuthStrategy.client_id / relay_url don't need a real DB
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("HOST_NAME").and_return("brain.test")
    allow(ENV).to receive(:fetch).with("HOST_USES_SSH", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("PORT").and_return("3334")
    allow(Setting).to receive(:get_value_of_key).and_call_original
    allow(Setting).to receive(:get_value_of_key)
      .with("indieauth_client_id_urls").and_return({
        "base_url" => "https://backupbrain.app",
        "redirect_url" => "https://backupbrain.app/indieauth-callback"
      })
  end

  def build_site_type(requires_pkce:)
    OauthSiteType.new(
      name: requires_pkce ? "Misskey" : "Mastodon",
      slug: requires_pkce ? "misskey" : "mastodon",
      registration_strategy: requires_pkce ? "indie_auth" : "mastodon_v1_apps",
      authorization_path: "/oauth/authorize",
      token_path: "/oauth/token",
      default_scopes: [requires_pkce ? "read:favorites" : "read"],
      requires_pkce: requires_pkce
    )
  end

  describe "POST #begin_auth" do
    let(:base_url) { "https://misskey.example.com" }

    context "when site_type requires PKCE" do
      let(:site_type) { build_site_type(requires_pkce: true) }
      let(:oauth_site) do
        OauthSite.new(
          _id: BSON::ObjectId.new,
          base_url: base_url,
          registered_url: local_url,
          oauth_site_type: site_type,
          client_id: OauthRegistration::IndieAuthStrategy.client_id,
          client_secret: nil,
          client_secret_expires_at: 0
        )
      end

      before do
        allow(OauthSiteType).to receive(:find).and_return(site_type)
        # rubocop:disable RSpec/VerifiedDoubles
        allow(OauthRegistration::IndieAuthStrategy).to receive(:new).and_return(
          double(register!: {client_id: OauthRegistration::IndieAuthStrategy.client_id, client_secret: nil, client_secret_expires_at: 0})
        )
        allow(OauthSite).to receive_messages(where: double(first: nil, count: 0, delete_all: nil), create!: oauth_site)
        # rubocop:enable RSpec/VerifiedDoubles
        allow(oauth_site).to receive(:_id).and_return(oauth_site._id)
      end

      it "includes code_challenge in the redirect URL" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        redirect_uri = response.location
        expect(redirect_uri).to include("code_challenge=")
      end

      it "includes code_challenge_method=S256 in the redirect URL" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        expect(response.location).to include("code_challenge_method=S256")
      end

      it "stores a code_verifier in the session" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        session_key = "pkce_#{oauth_site._id}"
        expect(session[session_key]).to be_present
      end

      it "uses the IndieAuth relay URL as redirect_uri" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        query = URI.decode_www_form(URI.parse(response.location).query).to_h
        expect(query["redirect_uri"]).to eq(OauthRegistration::IndieAuthStrategy.relay_url)
      end

      it "encodes state as Base64 JSON with id and u keys" do # rubocop:disable RSpec/MultipleExpectations
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        query = URI.decode_www_form(URI.parse(response.location).query).to_h
        state = JSON.parse(Base64.decode64(query["state"]))
        expect(state["id"]).to eq(oauth_site._id.to_s)
        expect(state["u"]).to eq(local_url)
      end
    end

    context "when site_type does not require PKCE (Mastodon path)" do
      let(:site_type) { build_site_type(requires_pkce: false) }
      let(:oauth_site) do
        OauthSite.new(
          _id: BSON::ObjectId.new,
          base_url: base_url,
          registered_url: local_url,
          oauth_site_type: site_type,
          client_id: "mastodon_client_id",
          client_secret: "mastodon_secret",
          client_secret_expires_at: 0
        )
      end

      before do
        allow(OauthSiteType).to receive(:find).and_return(site_type)
        # rubocop:disable RSpec/VerifiedDoubles
        allow(OauthRegistration::MastodonStrategy).to receive(:new).and_return(
          double(register!: {client_id: "mastodon_client_id", client_secret: "mastodon_secret", client_secret_expires_at: 0})
        )
        allow(OauthSite).to receive_messages(where: double(first: nil, count: 0, delete_all: nil), create!: oauth_site)
        # rubocop:enable RSpec/VerifiedDoubles
      end

      it "does not include code_challenge in the redirect URL" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        expect(response.location).not_to include("code_challenge")
      end

      it "does not include code_challenge_method in the redirect URL" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        expect(response.location).not_to include("code_challenge_method")
      end

      it "does not store a code_verifier in the session" do
        post :begin_auth, params: {base_url: base_url, site_type_id: site_type.id.to_s}
        expect(session.to_hash.keys).not_to include(match(/\Apkce_/))
      end
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe "GET #callback" do
    let(:code) { "auth_code_xyz" }
    let(:site_id) { BSON::ObjectId.new }
    let(:access_token_value) { "access_token_abc" }

    # rubocop:disable RSpec/VerifiedDoubles
    let(:oauth2_token) { double("OAuth2::AccessToken", token: access_token_value, expires_at: nil) }
    let(:auth_code_strategy) { double("OAuth2::Strategy::AuthCode") }
    let(:oauth2_client) { double("OAuth2::Client", auth_code: auth_code_strategy) }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      allow(OAuth2::Client).to receive(:new).and_return(oauth2_client)
    end

    context "when site_type requires PKCE" do
      let(:site_type) { build_site_type(requires_pkce: true) }
      let(:oauth_site) do
        instance_double(
          OauthSite,
          :_id => site_id,
          :client_id => "https://brain.test:3334",
          :client_secret => nil,
          :oauth_site_type => site_type,
          :base_url => "https://misskey.example.com",
          "access_token=" => nil,
          "access_token_expires_at=" => nil,
          :save! => true
        )
      end
      let(:verifier) { "stored_code_verifier" }
      let(:pkce_state) { Base64.strict_encode64(JSON.generate(id: site_id.to_s, u: "http://brain.test:3334")) }

      before do
        # rubocop:disable RSpec/VerifiedDoubles
        allow(OauthSite).to receive(:where).and_return(double(first: oauth_site))
        # rubocop:enable RSpec/VerifiedDoubles
        session["pkce_#{site_id}"] = verifier
        allow(auth_code_strategy).to receive(:get_token).and_return(oauth2_token)
      end

      it "passes code_verifier and relay redirect_uri to get_token" do
        # rubocop:disable RSpec/StubbedMock
        expect(auth_code_strategy).to receive(:get_token).with(
          code,
          hash_including(
            code_verifier: verifier,
            redirect_uri: OauthRegistration::IndieAuthStrategy.relay_url
          )
        ).and_return(oauth2_token)
        # rubocop:enable RSpec/StubbedMock
        get :callback, params: {code: code, state: pkce_state}
      end

      it "clears the verifier from the session after use" do
        get :callback, params: {code: code, state: pkce_state}
        expect(session["pkce_#{site_id}"]).to be_nil
      end
    end

    context "when site_type does not require PKCE (Mastodon path)" do
      let(:site_type) { build_site_type(requires_pkce: false) }
      let(:oauth_site) do
        instance_double(
          OauthSite,
          :_id => site_id,
          :client_id => "mastodon_client_id",
          :client_secret => "mastodon_secret",
          :oauth_site_type => site_type,
          :base_url => "https://mastodon.social",
          "access_token=" => nil,
          "access_token_expires_at=" => nil,
          :save! => true
        )
      end

      before do
        # rubocop:disable RSpec/VerifiedDoubles
        allow(OauthSite).to receive(:where).and_return(double(first: oauth_site))
        # rubocop:enable RSpec/VerifiedDoubles
        allow(auth_code_strategy).to receive(:get_token).and_return(oauth2_token)
      end

      it "does not pass code_verifier to get_token" do
        # rubocop:disable RSpec/StubbedMock
        expect(auth_code_strategy).to receive(:get_token).with(
          code,
          hash_not_including(:code_verifier)
        ).and_return(oauth2_token)
        # rubocop:enable RSpec/StubbedMock
        get :callback, params: {code: code, state: site_id.to_s}
      end
    end

    context "when state is a plain site_id (non-PKCE legacy format)" do
      let(:site_type) { build_site_type(requires_pkce: false) }
      let(:oauth_site) do
        instance_double(
          OauthSite,
          :_id => site_id,
          :client_id => "mastodon_client_id",
          :client_secret => "mastodon_secret",
          :oauth_site_type => site_type,
          :base_url => "https://mastodon.social",
          "access_token=" => nil,
          "access_token_expires_at=" => nil,
          :save! => true
        )
      end

      before do
        # rubocop:disable RSpec/VerifiedDoubles
        allow(OauthSite).to receive(:where).and_return(double(first: oauth_site))
        # rubocop:enable RSpec/VerifiedDoubles
        allow(auth_code_strategy).to receive(:get_token).and_return(oauth2_token)
      end

      it "resolves the site from the plain id and completes the callback" do
        get :callback, params: {code: code, state: site_id.to_s}
        expect(response).to redirect_to(root_path)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
