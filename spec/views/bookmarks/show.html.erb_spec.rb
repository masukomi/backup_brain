require "rails_helper"

RSpec.describe "bookmarks/show" do
  before do
    assign(:bookmark, Bookmark.create!(
      title: "Title",
      url: "Url",
      description: "Description",
      tags: "Tags"
    ))
  end

  # rubocop:disable RSpec/MultipleExpectations
  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Title/)
    expect(rendered).to match(/Url/)
    expect(rendered).to match(/Description/)
    expect(rendered).to match(/Tags/)
  end
  # rubocop:enable RSpec/MultipleExpectations
end
