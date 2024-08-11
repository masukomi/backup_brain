require "rails_helper"

RSpec.describe Tag do
  describe ".split_tags" do
    it "returns empty array for blank string" do
      expect(described_class.split_tags(" ")).to(eq([]))
    end

    it "splits comma only separated things" do
      expect(described_class.split_tags("foo,bar,baz")).to(eq(%w[foo bar baz]))
    end

    it "splits comma & space separated things" do
      expect(described_class.split_tags("foo, bar, baz")).to(eq(%w[foo bar baz]))
    end

    it "splits space separated things" do
      expect(described_class.split_tags("foo bar baz")).to(eq(%w[foo bar baz]))
    end

    it "does not include blank entries" do
      expect(described_class.split_tags("foo,,bar  baz")).to(eq(%w[foo bar baz]))
    end

    it "does not include duplicate entries" do
      expect(described_class.split_tags("foo bar, foo")).to(eq(%w[foo bar]))
    end

    it "downcases entries" do
      expect(described_class.split_tags("FOO Bar, bAz")).to(eq(%w[foo bar baz]))
    end
  end

  describe "valid_tags" do
    # tags are valid if they're
    # - not blank
    # - contain no whitespace (\t, \s, \n, \r, etc)
    # - have no upper case letters
    it "returns all valid tags" do
      expect(described_class.valid_tags(%w[foo bar baz])).to(eq(%w[foo bar baz]))
    end

    it "returns no invalid tags" do
      expect(described_class.valid_tags(
        [
          "Foo",
          "bar",
          "bAz",
          "",
          "     ",
          " foo ",
          "foo ",
          "  foo"
        ]
      )).to(eq(["bar"]))
    end
  end

  describe "single_tag_only" do
    it "lets a valid tag be valid" do
      expect(described_class.new(name: "foo").valid?).to(be(true))
    end

    it "marks a multi-word tag as invalid" do
      # under the covers this uses split_tags which we've tested
      # all the variations of above.
      expect(described_class.new(name: "foo bad").valid?).to(be(false))
    end
  end

  describe "multi-insert" do
    let(:temp_names) { %w[ex1 ex2 ex3] }

    after do
      described_class.where(name: {"$in" => temp_names}).destroy_all
    end

    describe ".create_many_by_name_if_needeed" do
      it "onlies create needed ones" do
        described_class.create(name: temp_names.first)
        expect {
          described_class.create_many_by_name_if_needed(temp_names)
        }.to change(described_class, :count).by(2)
      end
    end

    describe ".create_many_by_name" do
      it "creates many" do
        expect {
          described_class.create_many_by_name(temp_names)
        }.to change(described_class, :count).by(3)
      end
    end
  end
end
