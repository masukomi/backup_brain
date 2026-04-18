require "rails_helper"

RSpec.describe Setting do
  # Build a valid base setting — boolean type with a boolean inner value.
  let(:setting) { build(:setting) }

  after do
    described_class.destroy_all
  end

  # ---------------------------------------------------------------------------
  describe "#display_value_as" do
    context "when value_type is a simple non-string, non-hash type" do
      %w[boolean integer array text].each do |vtype|
        it "returns #{vtype.inspect} unchanged" do
          setting.value_type = vtype
          expect(setting.display_value_as).to(eq(vtype))
        end
      end
    end

    context "when value_type is 'string'" do
      before { setting.value_type = "string" }

      it "returns 'string' when the inner value has no newlines" do
        setting.value = {"value" => "hello"}
        expect(setting.display_value_as).to(eq("string"))
      end

      it "returns 'text' when the inner value has newlines" do
        setting.value = {"value" => "line one\nline two"}
        expect(setting.display_value_as).to(eq("text"))
      end

      it "returns 'string' when the inner value is nil" do
        setting.value = {"value" => nil}
        expect(setting.display_value_as).to(eq("string"))
      end
    end

    context "when value_type is 'hash'" do
      before { setting.value_type = "hash" }

      it "returns a hash mapping each key to 'string' for single-line string values" do
        setting.value = {"value" => {"base_url" => "https://example.com", "name" => "backup"}}
        expect(setting.display_value_as).to(eq({base_url: "string", name: "string"}))
      end

      it "maps a multi-line string value to 'text'" do
        setting.value = {"value" => {"notes" => "line one\nline two"}}
        expect(setting.display_value_as).to(eq({notes: "text"}))
      end

      it "maps an integer value to 'integer'" do
        setting.value = {"value" => {"timeout" => 30}}
        expect(setting.display_value_as).to(eq({timeout: "integer"}))
      end

      it "maps an array value to 'array'" do
        setting.value = {"value" => {"tags" => ["a", "b"]}}
        expect(setting.display_value_as).to(eq({tags: "array"}))
      end

      it "maps a true value to 'boolean'" do
        setting.value = {"value" => {"enabled" => true}}
        expect(setting.display_value_as).to(eq({enabled: "boolean"}))
      end

      it "maps a false value to 'boolean'" do
        setting.value = {"value" => {"enabled" => false}}
        expect(setting.display_value_as).to(eq({enabled: "boolean"}))
      end

      it "handles a hash with mixed types" do
        setting.value = {"value" => {
          "label" => "hello",
          "count" => 5,
          "active" => true,
          "items" => ["x"],
          "notes" => "a\nb"
        }}
        expect(setting.display_value_as).to(eq({
          label: "string",
          count: "integer",
          active: "boolean",
          items: "array",
          notes: "text"
        }))
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#inner_value" do
    it "returns the 'value' entry from the value hash" do
      setting.value = {"value" => 42}
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
      setting.value = {"value" => true}
      expect(setting.is_value_bool?).to(be(true))
    end

    it "returns true for false" do
      setting.value = {"value" => false}
      expect(setting.is_value_bool?).to(be(true))
    end

    it "returns false for non-boolean values", :aggregate_failures do
      [nil, 0, 1, "true", [], {}].each do |val|
        setting.value = {"value" => val}
        expect(setting.is_value_bool?).to(be(false), "expected false for #{val.inspect}")
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#is_boolean?" do
    it "returns true when value_type is 'boolean' and inner value is boolean" do
      setting.value_type = "boolean"
      setting.value = {"value" => true}
      expect(setting.is_boolean?).to(be(true))
    end

    it "returns false when value_type is not 'boolean'" do
      setting.value_type = "integer"
      setting.value = {"value" => true}
      expect(setting.is_boolean?).to(be(false))
    end

    it "returns false when value_type is 'boolean' but inner value is not boolean" do
      setting.value_type = "boolean"
      setting.value = {"value" => 1}
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
            setting.value = {"value" => val}
            expect(setting.valid?).to(be(true))
          end
        end

        wrong_value = valid_values.first.is_a?(TrueClass) ? 1 : true
        it "is invalid when inner value is the wrong type (#{wrong_value.inspect})" do
          setting.value = {"value" => wrong_value}
          expect(setting.valid?).to(be(false))
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe "#guarantee_value_default (before_save hook)" do
    it "sets value to {'value' => nil} when value is nil" do
      setting.value = nil
      setting.value_type = :boolean  # skip value type validation for this test
      # guarantee_value_default fires in before_save; call it directly
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({"value" => nil}))
    end

    it "does not overwrite value when it is already a hash with 'value' key" do
      setting.value = {"value" => false}
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({"value" => false}))
    end

    it "resets value to {'value' => nil} when value is a hash missing the 'value' key" do
      setting.value = {"other" => "stuff"}
      setting.send(:guarantee_value_default)
      expect(setting.value).to(eq({"value" => nil}))
    end
  end

  # ---------------------------------------------------------------------------
  describe ".get_value_of_key" do
    before do
      allow_any_instance_of(described_class).to(receive(:bust_cache))  # rubocop:disable RSpec/AnyInstance
    end

    it "returns the inner value for a known key" do
      s = build(:setting, lookup_key: "test_key", value: {"value" => "hello"}, value_type: :string)
      s.save(validate: false)
      described_class.instance_variable_set(:@cached_values, nil)
      expect(described_class.get_value_of_key("test_key")).to(eq("hello"))
    end

    it "raises UnknownSetting for an unknown key" do
      expect { described_class.get_value_of_key("no_such_key") }
        .to(raise_error(BackupBrain::Errors::UnknownSetting))
    end

    it "returns nil when the stored value hash contains nil" do
      s = build(:setting, lookup_key: "nil_key", value: {"value" => nil}, value_type: :boolean)
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
      s = build(:setting, lookup_key: "cache_test", value: {"value" => true})
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

  # ---------------------------------------------------------------------------
  describe "#set_value_and_type" do
    it "sets the inner value to the given object" do
      setting.set_value_and_type("hello")
      expect(setting.inner_value).to(eq("hello"))
    end

    it "sets value_type to 'boolean' for true" do
      setting.set_value_and_type(true)
      expect(setting.value_type).to(eq("boolean"))
    end

    it "sets value_type to 'boolean' for false" do
      setting.set_value_and_type(false)
      expect(setting.value_type).to(eq("boolean"))
    end

    it "sets value_type to 'integer' for an integer" do
      setting.set_value_and_type(42)
      expect(setting.value_type).to(eq("integer"))
    end

    it "sets value_type to 'string' for a single-line string" do
      setting.set_value_and_type("just one line")
      expect(setting.value_type).to(eq("string"))
    end

    it "sets value_type to 'text' for a multi-line string" do
      setting.set_value_and_type("line one\nline two")
      expect(setting.value_type).to(eq("text"))
    end

    it "sets value_type to 'array' for an array" do
      setting.set_value_and_type(["a", "b"])
      expect(setting.value_type).to(eq("array"))
    end

    it "sets value_type to 'hash' for a hash" do
      setting.set_value_and_type({"key" => "val"})
      expect(setting.value_type).to(eq("hash"))
    end

    it "sets value_type to 'string' for nil" do
      setting.set_value_and_type(nil)
      expect(setting.value_type).to(eq("string"))
    end

    it "preserves other keys already in value" do
      setting.value = {"value" => "old", "extra" => "data"}
      setting.set_value_and_type("new")
      expect(setting.value["extra"]).to(eq("data"))
    end

    it "initializes value to a hash when it is not already one" do
      setting.value = nil
      setting.set_value_and_type("hello")
      expect(setting.inner_value).to(eq("hello"))
    end
  end
end
