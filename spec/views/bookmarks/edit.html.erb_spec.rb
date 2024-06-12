require "rails_helper"

RSpec.describe "bookmarks/edit" do
  let(:bookmark) {
    Bookmark.create!(
      title: "MyString",
      url: "MyString",
      description: "MyString",
      tags: "MyString"
    )
  }

  before do
    assign(:bookmark, bookmark)
  end

  it "renders the edit bookmark form" do
    render

    assert_select "form[action=?][method=?]", bookmark_path(bookmark), "post" do
      assert_select "input[name=?]", "bookmark[title]"

      assert_select "input[name=?]", "bookmark[url]"

      assert_select "input[name=?]", "bookmark[description]"

      assert_select "input[name=?]", "bookmark[tags]"
    end
  end
end
