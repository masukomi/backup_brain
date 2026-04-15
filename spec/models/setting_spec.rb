require "rails_helper"

RSpec.describe Setting do
  # Build a valid base setting — boolean type with a boolean inner value.
  let(:setting) { build(:setting) }

  after do
    described_class.destroy_all
  end

  # ---------------------------------------------------------------------------
  describe "#inner_value" do
    it "returns the :value entry from the value hash" do
      setting.value = {value: 42}
      expect(setting.inner_value).to(eq(42))
    end

    it "returns nil when value is nil" do
      setting.value = nil
      expect(setting.inner_value).to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe "#is_value_bool?" do
    it "returns true for true" do
      setting.value = {value: true}
      expect(setting.is_value_bool?).to(be(true))
    end

    it "returns true for false" do
      setting.value = {value: false}
      expect(setting.is_value_bool?).to(be(true))
    end

    it "returns false for non-boolean values", :aggregate_failures do
      [nil, 0, 1, "true", [], {}].each do |val|
        setting.value = {value: val}
        expect(setting.is_value_bool?).to(be(false), "expected false for #{val.inspect}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#is_boolean?" do
    it "returns true when value_type is :boolean and inner value is boolean" do
      setting.value_type = :boolean
      setting.value = {value: true}
      expect(setting.is_boolean?).to(be(true))
    end

    it "returns false when value_type is not :boolean" do
      setting.value_type = :integer
      setting.value = {value: true}
      expect(setting.is_boolean?).to(be(false))
    end

    it "returns false when value_type is :boolean but inner value is not boolean" do
      setting.value_type = :boolean
      setting.value = {value: 1}
      expect(setting.is_boolean?).to(be(false))
    end
  end

  # ---------------------------------------------------------------------------
  describe "validation — #valid_value" do
    {
      boolean: [true, false],
      integer: [0, 42],
      string: ["", "hello"],
      array: [[], [1, 2]],
      hash: [{}, {"a" => 1}]
    }.each do |type, valid_values|
      context "when value_type: #{type}" do
        before { setting.value_type = type }

        valid_values.each do |val|
          it "is valid when inner value is #{val.inspect}" do
            setting.value = {value: val}
            expect(setting.valid?).to(be(true))
          end
        end

        wrong_value = valid_values.first.is_a?(TrueClass) ? 1 : true
        it "is invalid when inner value is the wrong type (#{wrong_value.inspect})" do
          setting.value = {value: wrong_value}
          expect(setting.valid?).to(be(false))
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#guarantee_value_default (before_save hook)" do
    it "sets value to {value: nil} when value is nil" do
      setting.value = nil
      setting.value_type = :boolean  # skip value type validation for this test
      # guarantee_value_default fires in before_save; call it directly
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({value: nil}))
    end

    it "does not overwrite value when it is already a hash with :value key" do
      setting.value = {value: false}
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({value: false}))
    end

    it "resets value to {value: nil} when value is a hash missing the :value key" do
      setting.value = {other: "stuff"}
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({value: nil}))
    end
  end

  # ---------------------------------------------------------------------------
  describe ".get_value_of_key" do
    before do
      allow_any_instance_of(described_class).to(receive(:bust_cache))  # rubocop:disable RSpec/AnyInstance
    end

    it "returns the inner value for a known key" do
      s = build(:setting, lookup_key: "test_key", value: {value: "hello"}, value_type: :string)
      s.save(validate: false)
      described_class.instance_variable_set(:@cached_values, nil)
      expect(described_class.get_value_of_key("test_key")).to(eq("hello"))
    end

    it "raises UnknownSetting for an unknown key" do
      expect { described_class.get_value_of_key("no_such_key") }
        .to(raise_error(BackupBrain::Errors::UnknownSetting))
    end

    it "returns nil when the stored value hash contains nil" do
      s = build(:setting, lookup_key: "nil_key", value: {value: nil}, value_type: :boolean)
      s.save(validate: false)
      described_class.instance_variable_set(:@cached_values, nil)
      expect(described_class.get_value_of_key("nil_key")).to(be_nil)
    end
  end

  # ---------------------------------------------------------------------------
  describe ".cached_values" do
    before do
      allow_any_instance_of(described_class).to(receive(:bust_cache))  # rubocop:disable RSpec/AnyInstance
      described_class.instance_variable_set(:@cached_values, nil)
    end

    it "returns a hash keyed by lookup_key" do
      s = build(:setting, lookup_key: "cache_test", value: {value: true})
      s.save(validate: false)
      described_class.instance_variable_set(:@cached_values, nil)
      expect(described_class.cached_values).to(have_key("cache_test"))
    end

    it "returns the same object on repeated calls (memoized)" do
      first  = described_class.cached_values
      second = described_class.cached_values
      expect(first.object_id).to(eq(second.object_id))
    end
  end
end
