# frozen_string_literal: true

require "spec_helper"
require "active_record"
require "active_support/testing/time_helpers"

# Versions are written by background jobs, so their ids follow job execution
# order. These specs run the jobs in reverse and check that version navigation
# follows `created_at` (the order of the changes) instead.
RSpec.describe PaperTrail::Background::Ordering do
  include ActiveSupport::Testing::TimeHelpers

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

  def at(time, &block)
    result = nil
    travel_to(time) { result = block.call }
    result
  end

  before(:context) do
    # paper_trail stores `object` as YAML, and Rails' safe loader rejects the
    # Time values in it unless they are explicitly permitted.
    @permitted_classes = ActiveRecord.yaml_column_permitted_classes
    ActiveRecord.yaml_column_permitted_classes = @permitted_classes + [Time, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone]

    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
    ActiveRecord::Migration.verbose = false
    ActiveRecord::Schema.define do
      create_table(:sprockets) do |t|
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

    Object.const_set(:Sprocket, Class.new(ActiveRecord::Base) do
      self.table_name = "sprockets"
      has_paper_trail(async: true)
    end)
  end

  after(:context) do
    ActiveRecord.yaml_column_permitted_classes = @permitted_classes
    Object.send(:remove_const, :Sprocket)
    ActiveRecord::Base.remove_connection
  end

  before do
    stub_const("VersionJob", job_class)
    PaperTrail::Background::Config.configure { |config| config.opt_in = true }
    PaperTrail::Version.delete_all
    Sprocket.delete_all
  end

  after { travel_back }

  # create (12:00), update to "b" (13:00), update to "c" (14:00); jobs then run
  # in reverse so ids are the opposite of chronological order.
  context "when the jobs ran in the reverse of the order the changes happened" do
    let!(:sprocket) { at(Time.utc(2020, 1, 1, 12)) { Sprocket.create!(name: "a") } }

    before do
      at(Time.utc(2020, 1, 1, 13)) { sprocket.update!(name: "b") }
      at(Time.utc(2020, 1, 1, 14)) { sprocket.update!(name: "c") }
      at(Time.utc(2020, 1, 9)) { run_jobs(queue.reverse) }
    end

    let(:created) { PaperTrail::Version.find_by!(event: "create") }
    # `object` holds the state before the change: V2 = "a", V3 = "b".
    let(:first_update) { PaperTrail::Version.find_by!(event: "update", created_at: Time.utc(2020, 1, 1, 13)) }
    let(:second_update) { PaperTrail::Version.find_by!(event: "update", created_at: Time.utc(2020, 1, 1, 14)) }

    it "has ids in the opposite order to the changes (the problem being solved)" do
      expect(created.id).to be > first_update.id
      expect(first_update.id).to be > second_update.id
    end

    describe "Version#previous" do
      it "returns the chronologically earlier version" do
        expect(second_update.previous).to eq(first_update)
        expect(first_update.previous).to eq(created)
        expect(created.previous).to be_nil
      end
    end

    describe "Version#next" do
      it "returns the chronologically later version" do
        expect(created.next).to eq(first_update)
        expect(first_update.next).to eq(second_update)
        expect(second_update.next).to be_nil
      end
    end

    describe "Version#index" do
      it "is the chronological position" do
        expect([created, first_update, second_update].map(&:index)).to eq([0, 1, 2])
      end
    end

    describe "Version#paper_trail_originator" do
      it "uses the chronologically previous version" do
        first_update.update_columns(whodunnit: "alice")
        created.update_columns(whodunnit: "bob")

        expect(first_update.paper_trail_originator).to eq("bob")
        expect(second_update.paper_trail_originator).to eq("alice")
      end
    end

    describe "#previous_version" do
      it "returns the most recent state for the live record" do
        expect(sprocket.reload.paper_trail.previous_version.name).to eq("b")
      end

      it "returns the state before a reified version" do
        expect(second_update.reify.paper_trail.previous_version.name).to eq("a")
      end

      it "is nil before the first version of the record" do
        expect(first_update.reify.paper_trail.previous_version).to be_nil
      end
    end

    describe "#next_version" do
      it "returns the state after a reified version" do
        expect(first_update.reify.paper_trail.next_version.name).to eq("b")
      end

      it "returns the live record after the latest version" do
        expect(second_update.reify.paper_trail.next_version.name).to eq("c")
      end
    end

    describe "#version_at" do
      it "reifies the record as it was at a point in time" do
        expect(sprocket.reload.paper_trail.version_at(Time.utc(2020, 1, 1, 13, 30)).name).to eq("b")
        expect(sprocket.reload.paper_trail.version_at(Time.utc(2020, 1, 1, 12, 30)).name).to eq("a")
      end
    end

    describe ".preceding / .subsequent" do
      it "still honours an explicit timestamp argument" do
        cutoff = Time.utc(2020, 1, 1, 13, 30)

        expect(PaperTrail::Version.preceding(cutoff, true)).to contain_exactly(created, first_update)
        expect(PaperTrail::Version.subsequent(cutoff, true)).to contain_exactly(second_update)
      end

      it "orders results chronologically" do
        expect(PaperTrail::Version.subsequent(created).to_a).to eq([first_update, second_update])
        expect(PaperTrail::Version.preceding(second_update).to_a).to eq([first_update, created])
      end
    end

    it "does not mix up versions of different records" do
      other = at(Time.utc(2020, 1, 1, 12, 30)) { Sprocket.create!(name: "other") }
      at(Time.utc(2020, 1, 9)) { run_jobs(queue.last(1)) }
      other_version = PaperTrail::Version.find_by!(item_id: other.id)

      expect(first_update.previous).to eq(created)
      expect(other_version.previous).to be_nil
      expect(other_version.next).to be_nil
    end
  end

  context "when versions share the same created_at" do
    it "falls back to id order" do
      time = Time.utc(2020, 1, 1, 12)
      sprocket = at(time) { Sprocket.create!(name: "a") }
      versions = Array.new(3) do |i|
        PaperTrail::Version.create!(item_type: "Sprocket", item_id: sprocket.id, event: "update", created_at: time + 1, whodunnit: i.to_s)
      end

      expect(versions[1].previous).to eq(versions[0])
      expect(versions[1].next).to eq(versions[2])
      expect(versions.map(&:index)).to eq([0, 1, 2])
    end
  end

  context "when the jobs ran in the same order as the changes" do
    it "behaves the same as id-based navigation" do
      sprocket = at(Time.utc(2020, 1, 1, 12)) { Sprocket.create!(name: "a") }
      at(Time.utc(2020, 1, 1, 13)) { sprocket.update!(name: "b") }
      at(Time.utc(2020, 1, 9)) { run_jobs(queue) }
      created, updated = PaperTrail::Version.order(:id).to_a

      expect(created.next).to eq(updated)
      expect(updated.previous).to eq(created)
      expect(updated.reify.name).to eq("a")
    end
  end
end
