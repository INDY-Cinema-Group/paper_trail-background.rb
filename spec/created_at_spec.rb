# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "active_support/testing/time_helpers"

# End-to-end coverage of version `created_at` with a real model, real
# paper_trail and an in-memory database. Jobs are captured instead of run so
# each example can run them late and out of order, like a busy queue would.
RSpec.describe "PaperTrail::Background created_at" do
  include ActiveSupport::Testing::TimeHelpers

  # Stands in for the host app's VersionJob.
  let(:queue) { [] }
  let(:job_class) do
    jobs = queue
    Class.new do
      include PaperTrail::Background::Job

      define_singleton_method(:perform_later) { |*args| jobs << args }
    end
  end

  def run_jobs(jobs)
    jobs.each { |args| job_class.new.perform(*args) }
  end

  before(:context) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:widgets) do |t|
        t.string :name
        t.timestamps
      end
      create_table(:gadgets) do |t|
        t.string :name
        t.timestamps
      end
      create_table(:versions) do |t|
        t.string :item_type, null: false
        t.bigint :item_id, null: false
        t.string :event, null: false
        t.string :whodunnit
        t.text :object
        t.text :object_changes
        t.datetime :created_at
      end
    end

    stub_widget = Class.new(ActiveRecord::Base) do
      self.table_name = "widgets"
      has_paper_trail(async: true)
    end
    stub_gadget = Class.new(ActiveRecord::Base) do
      self.table_name = "gadgets"
      has_paper_trail(async: true, synchronize_version_creation_timestamp: false)
    end
    Object.const_set(:Widget, stub_widget) unless Object.const_defined?(:Widget)
    Object.const_set(:Gadget, stub_gadget) unless Object.const_defined?(:Gadget)
  end

  after(:context) do
    ActiveRecord::Base.remove_connection
  end

  before do
    stub_const("VersionJob", job_class)
    PaperTrail::Background::Config.configure { |config| config.opt_in = true }
    PaperTrail::Version.delete_all
    Widget.delete_all
    Gadget.delete_all
  end

  after { travel_back }

  it "does not write any version until the job runs" do
    Widget.create!(name: "a")

    expect(PaperTrail::Version.count).to eq(0)
    expect(queue.size).to eq(1)
  end

  it "stamps a create version with the record's updated_at, not the job run time" do
    widget = freeze_time_at(Time.utc(2020, 1, 1, 12)) { Widget.create!(name: "a") }

    travel_to(Time.utc(2020, 1, 2)) { run_jobs(queue) }

    expect(PaperTrail::Version.last.created_at).to eq(widget.updated_at)
    expect(PaperTrail::Version.last.created_at).to eq(Time.utc(2020, 1, 1, 12))
  end

  it "stamps an update version with the record's updated_at, not the job run time" do
    widget = freeze_time_at(Time.utc(2020, 1, 1, 12)) { Widget.create!(name: "a") }
    freeze_time_at(Time.utc(2020, 1, 1, 13)) { widget.update!(name: "b") }

    travel_to(Time.utc(2020, 1, 5)) { run_jobs(queue) }

    update_version = PaperTrail::Version.find_by!(event: "update")
    expect(update_version.created_at).to eq(Time.utc(2020, 1, 1, 13))
  end

  it "stamps a destroy version with the time of the destroy, not the job run time" do
    widget = freeze_time_at(Time.utc(2020, 1, 1, 12)) { Widget.create!(name: "a") }
    freeze_time_at(Time.utc(2020, 1, 1, 14)) { widget.destroy! }

    travel_to(Time.utc(2020, 1, 5)) { run_jobs(queue) }

    destroy_version = PaperTrail::Version.find_by!(event: "destroy")
    expect(destroy_version.created_at).to eq(Time.utc(2020, 1, 1, 14))
  end

  it "stamps an update_columns version with the time of the change, not the job run time" do
    widget = freeze_time_at(Time.utc(2020, 1, 1, 12)) { Widget.create!(name: "a") }
    queue.clear
    freeze_time_at(Time.utc(2020, 1, 1, 15)) { widget.paper_trail.update_columns(name: "z") }

    travel_to(Time.utc(2020, 1, 5)) { run_jobs(queue) }

    expect(PaperTrail::Version.last.created_at).to eq(Time.utc(2020, 1, 1, 15))
  end

  it "uses the time of the change when synchronize_version_creation_timestamp is false" do
    gadget = freeze_time_at(Time.utc(2020, 1, 1, 12)) { Gadget.create!(name: "a") }

    travel_to(Time.utc(2020, 1, 5)) { run_jobs(queue) }

    expect(PaperTrail::Version.last.created_at).to eq(Time.utc(2020, 1, 1, 12))
    expect(gadget.updated_at).to eq(Time.utc(2020, 1, 1, 12))
  end

  context "when jobs run in the reverse of the order the changes happened" do
    let!(:widget) { freeze_time_at(Time.utc(2020, 1, 1, 12)) { Widget.create!(name: "a") } }

    before do
      freeze_time_at(Time.utc(2020, 1, 1, 13)) { widget.update!(name: "b") }
      freeze_time_at(Time.utc(2020, 1, 1, 14)) { widget.update!(name: "c") }
      freeze_time_at(Time.utc(2020, 1, 1, 15)) { widget.destroy! }

      travel_to(Time.utc(2020, 1, 9)) { run_jobs(queue.reverse) }
    end

    it "writes ids in job order, which is the wrong order" do
      events = PaperTrail::Version.order(:id).pluck(:event)

      expect(events).to eq(%w[destroy update update create])
    end

    it "still orders by created_at in the order the changes happened" do
      events = PaperTrail::Version.order(:created_at).pluck(:event)

      expect(events).to eq(%w[create update update destroy])
    end

    it "orders chronologically when sorted the way paper_trail sorts (created_at, then id)" do
      events = PaperTrail::Version.where(item_type: "Widget", item_id: widget.id).order(:created_at, :id).pluck(:event)

      expect(events).to eq(%w[create update update destroy])
    end

    it "keeps every version's created_at away from the job run time" do
      run_time = Time.utc(2020, 1, 9)

      expect(PaperTrail::Version.pluck(:created_at)).to all(be < run_time)
    end
  end

  # Helper: freeze time at `time` for the block and return the block's value.
  def freeze_time_at(time, &block)
    result = nil
    travel_to(time) { result = block.call }
    result
  end
end
