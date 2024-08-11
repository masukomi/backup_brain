require "rails_helper"

RSpec.describe Setting do
  describe "#valid_value" do
    let(:setting) { build(:setting) }

    it "isn't valid when unsupported type" do
      setting.value = Bookmark.new
      expect(setting.valid?).to(be(false))
    end

    it "is valid when supported type", :aggregate_failures do
      [true, false, 1, "foo", ["foo"], {"foo" => "bar"}].each do |val|
        setting = build(:setting)
        setting.value = val
        expect(setting.valid?).to(be(true), "#{val} wasn't valid")
      end
    end
  end
end
