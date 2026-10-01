require_relative "test_helper"
class GithubSyncTest < ActiveSupport::TestCase
  test "reimport attempts and fresh file mtime cannot postpone remote read of old evidence" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "github.json")
      File.write(path, JSON.generate({"observed_at" => 2.hours.ago.iso8601}))
      SourceState.create!(source: "github", state: "unknown", last_attempt_at: Time.current, last_success_at: 2.hours.ago)
      config_file = File.join(dir, "config.yml")
      File.write(config_file, {"projects" => [{"repositories" => ["example/app"]}], "sources" => {"github" => {"automatic" => true, "path" => path}}}.to_yaml)
      calls = 0
      collector = Object.new
      collector.define_singleton_method(:collect) do |repos, tracked:|
        calls += 1
        raise "Unexpected tracked PRs" unless tracked.empty?
        raise "Wrong repo" unless repos == ["example/app"]
        {version: 1, source: "github", state: "unknown", complete: false, observed_at: Time.current.iso8601(6), items: []}
      end
      sync = GithubSync.new(PanelConfig.new(config_file), collector: collector)
      sync.refresh
      assert_equal 1, calls
      assert SourceState.find_by(source: "github").last_success_at > 1.minute.ago
      sync.refresh
      assert_equal 1, calls
      travel 61.seconds do
        sync.refresh
        assert_equal 2, calls
      end
    end
  end
  test "poll cadence measures read start rather than postponing a slow successful read another minute" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "github.json"); config_file = File.join(dir, "config.yml")
      File.write(path, JSON.generate({observed_at: 57.seconds.ago.iso8601, poll_started_at: 61.seconds.ago.iso8601}))
      File.write(config_file, {"projects" => [{"repositories" => ["example/app"]}], "sources" => {"github" => {"automatic" => true, "path" => path}}}.to_yaml)
      calls = 0; collector = Object.new
      collector.define_singleton_method(:collect) { |_repos, tracked:| calls += 1; {version: 1, source: "github", state: "ok", complete: false, observed_at: Time.current.iso8601(6), items: []} }
      GithubSync.new(PanelConfig.new(config_file), collector: collector).refresh
      assert_equal 1, calls
    end
  end
  test "remote reconciliation clears an omitted request while preserving overlays and followup" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "github.json")
      config_file = File.join(dir, "config.yml")
      File.write(config_file, {"projects" => [{"repositories" => ["example/app"]}], "sources" => {"github" => {"automatic" => true, "path" => path}}}.to_yaml)
      item = row("example/app#12", "github", status: "open", overrides: {"title" => "My note"}, facts: {"bucket" => "review_requested"}, followup: {"required" => true})
      collector = Object.new
      collector.define_singleton_method(:collect) do |_repos, tracked:|
        raise "Missing stale request" unless tracked.include?("example/app#12")
        {version: 1, source: "github", state: "ok", complete: false, observed_at: Time.current.iso8601(6), items: [{id: "example/app#12", title: "Updated", status: "open", repository: "example/app", facts: {"bucket" => "review_resolved", "review_requested_for_viewer" => false, "viewer_review_state" => "APPROVED"}}]}
      end
      GithubSync.new(PanelConfig.new(config_file), collector: collector).refresh
      assert_equal "review_resolved", item.reload.facts["bucket"]
      assert_equal "My note", item.display(:title)
      assert item.followup["required"]
      assert_not ItemActivity.for(item).needs_you?
    end
  end
  test "rate limit and failure backoff retain source success and don't retry on forced refresh" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "github.json"); config_file = File.join(dir, "config.yml")
      File.write(config_file, {"projects" => [{"repositories" => ["example/app"]}], "sources" => {"github" => {"automatic" => true, "path" => path}}}.to_yaml)
      old = row("example/app#12", "github", facts: {"bucket" => "review_requested"})
      state = SourceState.create!(source: "github", state: "ok", last_success_at: 2.minutes.ago)
      previous_success = state.last_success_at
      calls = 0; collector = Object.new
      collector.define_singleton_method(:collect) { |_repos, tracked:| calls += 1; raise GithubSnapshot::RateLimited.new(5.minutes.from_now) }
      sync = GithubSync.new(PanelConfig.new(config_file), collector: collector)
      sync.refresh; sync.refresh(force: true)
      assert_equal 1, calls
      assert_equal "unavailable", state.reload.state
      assert_equal previous_success, state.last_success_at
      assert_equal "review_requested", old.reload.facts["bucket"]
      assert_not ItemActivity.for(old, source_state: state).needs_you?
      travel 301.seconds do
        sync.refresh
        assert_equal 2, calls
      end
    end
  end
end
