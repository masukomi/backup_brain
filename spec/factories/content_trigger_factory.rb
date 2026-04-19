FactoryBot.define do
  factory :content_trigger do
    sequence(:name) { |n| "Content Trigger #{n}" }
    simple_triggers  { ["youtube", "youtu.be"] }
    case_insensitive { true }
    mark_as_private  { false }
    mark_as_sensitive { false }
    mark_to_read     { false }
    tags             { [] }
  end
end
