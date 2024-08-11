require "securerandom"

FactoryBot.define do
  factory :setting do
    lookup_key  { SecureRandom.uuid }
    summary     { "bogus summary" }
    description { "bogus description" }
    visible     { true }
    value       { 1 }
  end
end
