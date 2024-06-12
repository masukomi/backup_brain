require "rails_helper"

RSpec.describe "bookmarks/new" do
  before do
    assign(:bookmark, Bookmark.new(
      title: "MyString",
      url: "MyString",
      description: "MyString",
      tags: "MyString"
    ))
  end

  it "renders new bookmark form" do
    render

    assert_select "form[action=?][method=?]", bookmarks_path, "post" do
      assert_select "input[name=?]", "bookmark[title]"

      assert_select "input[name=?]", "bookmark[url]"

      assert_select "input[name=?]", "bookmark[description]"

      assert_select "input[name=?]", "bookmark[tags]"
    end
  end
end
