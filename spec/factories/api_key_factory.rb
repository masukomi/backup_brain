FactoryBot.define do
  factory :api_key do
    name { "test key" }
    permissions { ["read:bookmarks", "write:bookmarks", "read:notes", "write:notes"] }

    factory :expired_api_key do
      name { "expired key" }
      expiration_date { Date.current - 1 }
    end

    factory :read_only_api_key do
      name { "read only key" }
      permissions { ["read:bookmarks", "read:notes"] }
    end

    factory :notes_only_api_key do
      name { "notes only key" }
      permissions { ["read:notes"] }
    end
  end
end
