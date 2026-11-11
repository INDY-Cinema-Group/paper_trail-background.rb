# frozen_string_literal: true

require "spec_helper"

WithData = Struct.new(:data) do
  def changed_notably? = true
end
WithVersionClass = Struct.new(:version_class)

class SuperDummyClass
  def record_create
    @record = 1
  end

  def record_update(record)
    @record = record
  end

  def record_destroy(record)
    @record = record
  end

  def record_update_columns(record)
    @record = record
  end
end

class DummyClass < SuperDummyClass
  include PaperTrail::Background

  def initialize(options: {}, record: nil)
    @options = options
    @record = record
    super()
  end

  def enabled?
    @options[:enabled]
  end

  def data_for_create
    {}
  end

  def data_for_destroy
    {}
  end

  def data_for_update_columns
    {}
  end

  def force
    true
  end
end

class VersionJob
  def self.perform_later(*args); end
end

RSpec.describe PaperTrail::Background do
  before do
    allow(VersionJob).to receive(:perform_later)
  end

  describe "#record_create" do
    it "does not trigger a write if not enabled" do
      DummyClass.new(options: { enabled: false }).record_create

      expect(VersionJob).not_to have_received(:perform_later)
    end

    context "when enabled and opt_in config is enabled" do
      let(:record) { double("SomeRecord") }

      before do
        PaperTrail::Background::Config.configure do |config|
          config.opt_in = true
        end
      end

      it "does not trigger a write if record is opted in but async is blank" do
        allow(record).to receive(:paper_trail_event).and_return(async: nil)
        allow(record).to receive(:paper_trail_options).and_return(async: nil)
        allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))

        DummyClass.new(options: { enabled: true }, record:).record_create

        expect(VersionJob).not_to have_received(:perform_later)
      end

      it "triggers a write if record is opted in and async is true" do
        allow(record).to receive(:paper_trail_options).and_return(async: true)
        allow(PaperTrail::Events::Create).to receive(:new).and_return(WithData.new({}))
        allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))
        allow(record.class).to receive(:after_transaction).and_yield

        DummyClass.new(options: { enabled: true }, record:).record_create

        expect(VersionJob).to have_received(:perform_later)
      end
    end
  end

  describe "#record_destroy" do
    it "does not trigger a write if not enabled" do
      DummyClass.new(options: { enabled: false }).record_destroy("after")

      expect(VersionJob).not_to have_received(:perform_later)
    end

    context "when enabled and opt_in config is enabled" do
      let(:record) { double("SomeRecord") }

      before do
        PaperTrail::Background::Config.configure do |config|
          config.opt_in = true
        end
      end

      it "does not trigger a write if record is opted in but async is blank" do
        allow(record).to receive(:paper_trail_options).and_return(async: nil)

        DummyClass.new(options: { enabled: true }, record:).record_destroy("after")

        expect(VersionJob).not_to have_received(:perform_later)
      end

      it "does not trigger a write if record is new" do
        allow(record).to receive_messages(paper_trail_options: { async: true }, new_record?: true)

        DummyClass.new(options: { enabled: true }, record:).record_destroy("after")

        expect(VersionJob).not_to have_received(:perform_later)
      end

      it "triggers a write if record is opted in and async is true" do
        allow(record).to receive_messages(paper_trail_options: { async: true }, new_record?: false)
        allow(PaperTrail::Events::Destroy).to receive(:new).and_return(WithData.new({}))
        allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))
        allow(record.class).to receive(:after_transaction).and_yield

        DummyClass.new(options: { enabled: true }, record:).record_destroy("after")

        expect(VersionJob).to have_received(:perform_later)
      end
    end
  end

  describe "#record_update" do
    it "does not trigger a write if not enabled" do
      DummyClass.new(options: { enabled: false }).record_update(force: true, in_after_callback: true, is_touch: false)

      expect(VersionJob).not_to have_received(:perform_later)
    end

    context "when enabled and opt_in config is enabled" do
      let(:record) { double("SomeRecord") }

      before do
        PaperTrail::Background::Config.configure do |config|
          config.opt_in = true
        end
      end

      it "does not trigger a write if record is opted in but async is blank" do
        allow(record).to receive(:paper_trail_options).and_return(async: nil)

        DummyClass.new(options: { enabled: true }, record:).record_update(force: true, in_after_callback: true, is_touch: false)

        expect(VersionJob).not_to have_received(:perform_later)
      end

      it "triggers a write if record is opted in and async is true" do
        allow(record).to receive_messages(paper_trail_options: { async: true }, new_record?: false)
        allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({}))
        allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))
        allow(record.class).to receive(:after_transaction).and_yield

        DummyClass.new(options: { enabled: true }, record:).record_update(force: true, in_after_callback: true, is_touch: false)

        expect(VersionJob).to have_received(:perform_later)
      end
    end
  end

  describe "#record_update_columns" do
    it "does not trigger a write if not enabled" do
      DummyClass.new(options: { enabled: false }).record_update_columns({})

      expect(VersionJob).not_to have_received(:perform_later)
    end

    context "when enabled and opt_in config is enabled" do
      let(:record) { double("SomeRecord") }

      before do
        PaperTrail::Background::Config.configure do |config|
          config.opt_in = true
        end
      end

      it "does not trigger a write if record is opted in but async is blank" do
        allow(record).to receive(:paper_trail_options).and_return(async: nil)

        DummyClass.new(options: { enabled: true }, record:).record_update_columns({})

        expect(VersionJob).not_to have_received(:perform_later)
      end

      it "triggers a write if record is opted in and async is true" do
        allow(record).to receive_messages(paper_trail_options: { async: true }, new_record?: false)
        allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({}))
        allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))
        allow(record.class).to receive(:after_transaction).and_yield

        DummyClass.new(options: { enabled: true }, record:).record_update_columns({})

        expect(VersionJob).to have_received(:perform_later)
      end
    end
  end

  describe "created_at" do
    let(:record) { double("SomeRecord") }
    let(:updated_at) { Time.utc(2020, 1, 1, 12, 0, 0) }
    let(:now) { Time.utc(2024, 6, 1, 8, 0, 0) }
    let(:options) { { async: true } }

    before do
      PaperTrail::Background::Config.configure { |config| config.opt_in = true }
      allow(record).to receive_messages(paper_trail_options: options, new_record?: false, updated_at:)
      allow(record.class).to receive(:paper_trail).and_return(WithVersionClass.new(Class))
      allow(record.class).to receive(:after_transaction).and_yield
      allow(Time).to receive(:current).and_return(now)
    end

    def written_data
      attrs = nil
      expect(VersionJob).to have_received(:perform_later) { |_klass, data, _event| attrs = data }
      attrs
    end

    it "uses the record's updated_at on create" do
      allow(PaperTrail::Events::Create).to receive(:new).and_return(WithData.new({}))
      DummyClass.new(options: { enabled: true }, record:).record_create

      expect(written_data[:created_at]).to eq(updated_at)
    end

    it "uses the record's updated_at on update" do
      allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({}))
      DummyClass.new(options: { enabled: true }, record:).record_update(force: true, in_after_callback: true, is_touch: false)

      expect(written_data[:created_at]).to eq(updated_at)
    end

    it "uses the time of the change on destroy" do
      allow(PaperTrail::Events::Destroy).to receive(:new).and_return(WithData.new({}))
      DummyClass.new(options: { enabled: true }, record:).record_destroy("after")

      expect(written_data[:created_at]).to eq(now)
    end

    it "uses the time of the change on update_columns" do
      allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({}))
      DummyClass.new(options: { enabled: true }, record:).record_update_columns({})

      expect(written_data[:created_at]).to eq(now)
    end

    it "does not overwrite a created_at already present in the data" do
      explicit = Time.utc(2019, 1, 1)
      allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({ created_at: explicit }))
      DummyClass.new(options: { enabled: true }, record:).record_update(force: true, in_after_callback: true, is_touch: false)

      expect(written_data[:created_at]).to eq(explicit)
    end

    context "when synchronize_version_creation_timestamp is false" do
      let(:options) { { async: true, synchronize_version_creation_timestamp: false } }

      it "uses the time of the change instead of updated_at" do
        allow(PaperTrail::Events::Update).to receive(:new).and_return(WithData.new({}))
        DummyClass.new(options: { enabled: true }, record:).record_update(force: true, in_after_callback: true, is_touch: false)

        expect(written_data[:created_at]).to eq(now)
      end
    end
  end
end
