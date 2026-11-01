FactoryBot.define do
  factory :s3_bucket do
    sequence(:nickname) { |n| "bucket #{n}" }
    enabled { true }
    primary { false }
    endpoint { "http://localhost:9000" }
    region { "us-east-1" }
    sequence(:name) { |n| "bb-archives-#{n}" }
    access_key_id { "key-id" }
    secret_access_key { "key-secret" }
    key_prefix { "" }
    presigned_url_expiry { 600 }
    path_style_urls { true }
  end
end
