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
      collector.define_singleton_method(:collect) do |repos|
        calls += 1
        raise "Wrong repo" unless repos == ["example/app"]
        {version: 1, source: "github", state: "unknown", complete: false, observed_at: Time.current.iso8601, items: []}
      end
      sync = GithubSync.new(PanelConfig.new(config_file), collector: collector)
      sync.refresh
      assert_equal 1, calls
      assert SourceState.find_by(source: "github").last_success_at > 1.minute.ago
      sync.refresh
      assert_equal 1, calls
    end
  end
end
