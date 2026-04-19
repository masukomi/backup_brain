require "rails_helper"

# Plain Ruby test double that includes the module — no Mongoid needed.
class FakeTriggersModel
  include BackupBrain::Triggers

  attr_accessor :mark_to_read, :mark_as_private, :mark_as_sensitive, :tags

  def initialize(attrs = {})
    @mark_to_read      = attrs.fetch(:mark_to_read, false)
    @mark_as_private   = attrs.fetch(:mark_as_private, false)
    @mark_as_sensitive = attrs.fetch(:mark_as_sensitive, false)
    @tags              = attrs.fetch(:tags, [])
  end
end

class FakeTargetDoc
  attr_accessor :to_read, :private, :sensitive, :tags

  def initialize(attrs = {})
    @to_read   = attrs.fetch(:to_read, false)
    @private   = attrs.fetch(:private, false)
    @sensitive = attrs.fetch(:sensitive, false)
    @tags      = attrs.fetch(:tags, [])
  end

  def has_attribute?(attr)
    respond_to?(attr)
  end

  def save!
  end
end

RSpec.describe BackupBrain::Triggers do
  let(:doc) { FakeTargetDoc.new }

  describe "#apply_to" do
    context "when mark_to_read is true" do
      let(:trigger) { FakeTriggersModel.new(mark_to_read: true) }

      it "sets to_read on the document" do
        trigger.apply_to(doc)
        expect(doc.to_read).to be true
      end
    end

    context "when mark_to_read is false" do
      let(:trigger) { FakeTriggersModel.new(mark_to_read: false) }

      it "does not set to_read" do
        trigger.apply_to(doc)
        expect(doc.to_read).to be false
      end
    end

    context "when mark_as_private is true" do
      let(:trigger) { FakeTriggersModel.new(mark_as_private: true) }

      it "sets private on the document" do
        trigger.apply_to(doc)
        expect(doc.private).to be true
      end
    end

    context "when mark_as_private is false" do
      let(:trigger) { FakeTriggersModel.new(mark_as_private: false) }

      it "does not set private" do
        trigger.apply_to(doc)
        expect(doc.private).to be false
      end
    end

    context "when mark_as_sensitive is true" do
      let(:trigger) { FakeTriggersModel.new(mark_as_sensitive: true) }

      it "sets sensitive on the document" do
        trigger.apply_to(doc)
        expect(doc.sensitive).to be true
      end
    end

    context "when mark_as_sensitive is false" do
      let(:trigger) { FakeTriggersModel.new(mark_as_sensitive: false) }

      it "does not set sensitive" do
        trigger.apply_to(doc)
        expect(doc.sensitive).to be false
      end
    end

    context "when tags are present on the trigger" do
      let(:trigger) { FakeTriggersModel.new(tags: ["video", "media"]) }

      it "adds trigger tags not already on the document" do
        doc.tags = ["existing"]
        trigger.apply_to(doc)
        expect(doc.tags).to include("video", "media", "existing")
      end

      it "does not duplicate tags already on the document" do
        doc.tags = ["video"]
        trigger.apply_to(doc)
        expect(doc.tags.count("video")).to eq(1)
      end
    end

    context "when trigger has no tags" do
      let(:trigger) { FakeTriggersModel.new(tags: []) }

      it "does not alter the document tags" do
        doc.tags = ["foo"]
        trigger.apply_to(doc)
        expect(doc.tags).to eq(["foo"])
      end
    end

    context "when the document does not respond to an attribute" do
      let(:trigger) { FakeTriggersModel.new(tags: ["video"], mark_as_private: true) }

      it "does not raise an error for missing attributes" do
        tagless_doc = Object.new
        def tagless_doc.has_attribute?(_)
          false
        end
        expect { trigger.apply_to(tagless_doc) }.not_to raise_error
      end
    end
  end

  describe "#apply_to!" do
    let(:trigger) { FakeTriggersModel.new(mark_as_private: true) }

    it "applies trigger settings to the document" do
      allow(doc).to receive(:save!)
      trigger.apply_to!(doc)
      expect(doc.private).to be true
    end

    it "calls save! on the document" do
      allow(doc).to receive(:save!)
      trigger.apply_to!(doc)
      expect(doc).to have_received(:save!)
    end
  end
end
