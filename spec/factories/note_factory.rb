FactoryBot.define do
  factory :note do
    title { "a note" }
    string_data { "the contents of a note" }
    private { false }
  end
end
