# lib/emoji_helper_spec.rb

require "spec_helper"
require "rails_helper"

class FakeModel
  include BackupBrain::EmojiHelper

  EMOJIFIABLE_FIELDS = [:content, :title]

  attr_accessor :content, :title
  def initialize(content, title)
    @content = content
    @title = title
  end
end

RSpec.describe BackupBrain::EmojiHelper do
  it "does not change content without text emoji", :aggregate_failures do
    boring_title = "my boring title"
    boring_content = "my boring content"
    fm = FakeModel.new(boring_content, boring_title)
    fm.emojify_default_fields
    expect(fm.content).to(eq(boring_content))
    expect(fm.title).to(eq(boring_title))
  end

  it "does not change content with real emoji", :aggregate_failures do
    emoji_title = "my 🐄 title"
    emoji_content = "my 🥛 content"
    fm = FakeModel.new(emoji_content, emoji_title)
    fm.emojify_default_fields
    expect(fm.content).to(eq(emoji_content))
    expect(fm.title).to(eq(emoji_title))
  end

  it "changes content with text emoji", :aggregate_failures do
    initial_content = "my :cat: content"
    initial_title = "my :dog: title"
    fm = FakeModel.new(initial_content, initial_title)
    fm.emojify_default_fields
    expect(fm.title).to(eq("my 🐶 title"))
    expect(fm.content).to(eq("my 🐱 content"))
  end
end
