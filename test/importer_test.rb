require_relative "test_helper"
class ImporterTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "codex.json")
    config = Object.new
    config.define_singleton_method(:source_path) { |_source| @path }
    config.instance_variable_set(:@path, @path)
    config.define_singleton_method(:project_for) { |_row| "example" }
    @importer = SnapshotImporter.new(config)
  end
  teardown { FileUtils.remove_entry(@dir) }
  def snapshot(items, **attrs)
    File.write(@path, JSON.generate({ version: 1, source: "codex", state: "ok", complete: true, observed_at: Time.current.iso8601(6), items: items }.merge(attrs)))
    @importer.import_source("codex")
  end
  test "refresh preserves local correction snooze and production confirmation" do
    original = row(overrides: { "title" => "Local title" }, snoozed_until: 1.day.from_now, followup: { "deployed" => { "done" => true, "evidence" => "release log" } })
    snapshot([{ id: "a", title: "New source title", facts: { agent_finished: true, task_completed: false } }])
    original.reload
    assert_equal "New source title", original.title
    assert_equal "Local title", original.display(:title)
    assert original.hidden?
    assert original.followup.dig("deployed", "done")
    assert_equal false, original.facts["task_completed"]
    assert_match "confirm", original.next_action
  end
  test "user-confirmed archive hide remains local and reversible across refresh" do
    original = row(overrides: {"archive_confirmation" => {"provenance" => "user-confirmed archived", "recorded_at" => Time.current.iso8601}}, dismissed: true)
    snapshot([{id: "a", title: "Refreshed", facts: {archived: nil}}])
    assert original.reload.hidden?
    assert_equal "user-confirmed archived", original.overrides.dig("archive_confirmation", "provenance")
    assert_nil original.facts["archived"]
    original.update!(dismissed: false, snoozed_until: nil)
    assert_not original.hidden?
  end
  test "malformed snapshot rolls back entire import and preserves previous data" do
    original = row
    snapshot([{ id: "a", title: "Would update" }, { id: "b" }])
    assert_equal "Source title", original.reload.title
    assert_equal 1, Item.count
    assert_equal "unavailable", SourceState.find_by(source: "codex").state
  end
  test "only complete successful snapshot marks missing items" do
    original = row(observed_at: 1.hour.ago)
    snapshot([], complete: false)
    assert_not original.reload.missing_from_snapshot
    snapshot([], state: "unknown")
    assert_not original.reload.missing_from_snapshot
    snapshot([])
    assert original.reload.missing_from_snapshot
    assert_equal 1, Item.count
  end
  test "missing or invalid source retains old observation time" do
    original = row(observed_at: 3.days.ago)
    @importer.import_source("codex")
    assert original.reload.stale?(24)
    assert_equal "unavailable", SourceState.find_by(source: "codex").state
  end
  test "failed attempt does not advance the last successful observation" do
    snapshot([{id: "a", title: "Snapshot"}])
    state = SourceState.find_by(source: "codex")
    successful = state.last_success_at
    snapshot([], state: "unavailable")
    assert_equal successful, state.reload.last_success_at
    assert state.last_attempt_at.present?
    assert_equal 1, Item.count
  end
  test "old snapshots cannot overwrite new facts" do
    original = row
    snapshot([{ id: "a", title: "Old" }], observed_at: 2.days.ago.iso8601)
    assert_equal "Source title", original.reload.title
  end
  test "duplicate ids are rejected" do
    snapshot([{ id: "a", title: "One" }, { id: "a", title: "Two" }])
    assert_equal 0, Item.count
  end
end
