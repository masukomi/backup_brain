FactoryBot.define do
  factory :tag do
    name { "programming" }
  end
  factory :orphaned_tag, class: 'Tag' do
    name { "orphan" }
  end
end
