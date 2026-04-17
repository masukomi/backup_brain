require "rails_helper"

RSpec.describe OauthRegistration::Rfc7591Strategy do
  subject(:strategy) do
    described_class.new(
      base_url: base_url,
      callback_url: "https://brain.example.com/remote_authorizations/callback",
      local_url: "https://brain.example.com",
      site_type: site_type
    )
  end

  let(:base_url) { "https://example.social" }
  let(:site_type) { instance_double(OauthSiteType, default_scopes: ["read"]) }

  # rubocop:disable RSpec/VerifiedDoubles
  def successful_response(body)
    resp = double("Net::HTTPSuccess")
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(resp).to receive(:body).and_return(body.to_json)
    resp
  end

  def not_found_response
    resp = double("Net::HTTPNotFound")
    allow(resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    resp
  end
  # rubocop:enable RSpec/VerifiedDoubles

  describe "#discover_registration_uri" do
    context "when /.well-known/oauth-authorization-server returns a registration_endpoint" do
      let(:registration_endpoint) { "https://example.social/oauth2/register" }

      before do
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/oauth-authorization-server"))
          .and_return(successful_response({"registration_endpoint" => registration_endpoint}))
      end

      it "returns the registration_endpoint URI" do
        result = strategy.send(:discover_registration_uri)
        expect(result).to eq(URI.parse(registration_endpoint))
      end

      it "does not check /.well-known/openid-configuration" do
        expect(Net::HTTP).not_to receive(:get_response)
          .with(URI.join(base_url, ".well-known/openid-configuration"))
        strategy.send(:discover_registration_uri)
      end
    end

    context "when RFC 8414 returns 404 but OpenID Connect returns a registration_endpoint" do
      let(:oidc_endpoint) { "https://example.social/connect/register" }

      before do
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/oauth-authorization-server"))
          .and_return(not_found_response)
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/openid-configuration"))
          .and_return(successful_response({"registration_endpoint" => oidc_endpoint}))
      end

      it "returns the registration_endpoint from the OIDC document" do
        result = strategy.send(:discover_registration_uri)
        expect(result).to eq(URI.parse(oidc_endpoint))
      end
    end

    context "when both RFC 8414 and OIDC return 404" do
      before do
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/oauth-authorization-server"))
          .and_return(not_found_response)
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/openid-configuration"))
          .and_return(not_found_response)
      end

      it "falls back to /oauth2/register" do
        result = strategy.send(:discover_registration_uri)
        expect(result).to eq(URI.join(base_url, "/oauth2/register"))
      end
    end

    context "when RFC 8414 document exists but has no registration_endpoint key" do
      before do
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/oauth-authorization-server"))
          .and_return(successful_response({"issuer" => base_url, "token_endpoint" => "#{base_url}/oauth/token"}))
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/openid-configuration"))
          .and_return(not_found_response)
      end

      it "falls through to the /oauth2/register fallback" do
        result = strategy.send(:discover_registration_uri)
        expect(result).to eq(URI.join(base_url, "/oauth2/register"))
      end
    end

    context "when a discovery endpoint raises a connection error" do
      before do
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/oauth-authorization-server"))
          .and_raise(Errno::ECONNREFUSED, "connection refused")
        allow(Net::HTTP).to receive(:get_response)
          .with(URI.join(base_url, ".well-known/openid-configuration"))
          .and_raise(Errno::ECONNREFUSED, "connection refused")
        allow(Rails.logger).to receive(:warn)
      end

      it "falls back to /oauth2/register" do
        result = strategy.send(:discover_registration_uri)
        expect(result).to eq(URI.join(base_url, "/oauth2/register"))
      end

      it "logs a warning for each failed endpoint" do
        expect(Rails.logger).to receive(:warn).at_least(:twice)
        strategy.send(:discover_registration_uri)
      end
    end
  end
end
