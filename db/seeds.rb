OauthSiteType.find_or_create_by!(slug: "mastodon") do |t|
  t.name                  = "Mastodon"
  t.slug                  = "mastodon"
  t.description           = "Connect to any Mastodon instance"
  t.registration_strategy = "mastodon_v1_apps"
  t.registration_path     = "/api/v1/apps"
  t.authorization_path    = "/oauth/authorize"
  t.token_path            = "/oauth/token"
  t.default_scopes        = ["read"]
end
