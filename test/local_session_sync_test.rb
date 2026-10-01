require_relative "test_helper"
class LocalSessionSyncTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "claude.json")
    config_file = File.join(@dir, "config.yml")
    File.write(config_file, {"projects" => [{"id" => "configured", "local_paths" => ["/explicit/project"]}],
      "sources" => {"claude" => {"automatic" => true, "path" => @path}}}.to_yaml)
    @config = PanelConfig.new(config_file)
  end
  teardown { FileUtils.remove_entry(@dir) }
  test "reads only explicit directories, imports partial history and throttles refresh" do
    calls = 0
    reader = lambda do |directories|
      assert_equal ["/explicit/project"], directories
      calls += 1
      {"version" => 1, "source" => "claude", "state" => "unknown", "complete" => false,
       "observed_at" => Time.current.iso8601, "items" => [{"id" => "session", "title" => "Session", "cwd" => directories.first,
       "facts" => {"agent_finished" => nil, "task_completed" => nil}}]}
    end
    sync = LocalSessionSync.new(@config, reader: reader)
    sync.refresh
    sync.refresh
    assert_equal 1, calls
    assert_equal "configured", Item.first.project_id
    assert_nil Item.first.facts["task_completed"]
    sync.refresh(force: true)
    assert_equal 2, calls
  end
  test "failed reader preserves confirmed source data and local corrections" do
    item = row("old", "claude", overrides: {"title" => "Local correction"})
    success = SourceState.create!(source: "claude", state: "unknown", last_success_at: 1.hour.ago)
    LocalSessionSync.new(@config, reader: ->(_) { raise IOError, "private diagnostic" }).refresh(force: true)
    assert_equal "unavailable", success.reload.state
    assert success.last_success_at < 30.minutes.ago
    assert_equal "Local correction", item.reload.display(:title)
    assert_not_includes success.message, "private diagnostic"
    assert_equal [], JSON.parse(File.read(@path))["items"]
  end
  test "automatic reads are opt in" do
    @config.settings["sources"]["claude"]["automatic"] = false
    LocalSessionSync.new(@config, reader: ->(_) { flunk "Must not read" }).refresh
    assert_not File.exist?(@path)
  end
end
