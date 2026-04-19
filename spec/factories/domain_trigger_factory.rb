FactoryBot.define do
  factory :domain_trigger do
    sequence(:domain) { |n| "example#{n}.com" }
    mark_as_private   { false }
    mark_as_sensitive { false }
    mark_to_read      { false }
    tags              { [] }
  end
end
