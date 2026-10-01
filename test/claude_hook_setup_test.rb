require_relative "test_helper"
require_relative "../lib/claude_hook_setup"
class ClaudeHookSetupTest < ActiveSupport::TestCase
  test "personal hook merge preserves permissions and unrelated hooks, is idempotent and removable" do
    Dir.mktmpdir do |root|
      project = File.join(root, "project with spaces"); FileUtils.mkdir_p(File.join(project, ".claude"))
      FileUtils.mkdir_p(File.join(root, "config"))
      FileUtils.cp(Rails.root.join("config/claude-hooks.example.json"), File.join(root, "config/claude-hooks.example.json"))
      File.write(File.join(root, "config/panel.yml"), {"projects" => [{"local_paths" => [project]}], "sources" => {"claude" => {"path" => "data/claude.json"}}}.to_yaml)
      original = {"permissions" => {"allow" => ["Read"]}, "hooks" => {"Stop" => [{"hooks" => [{"type" => "command", "command" => "existing-command"}]}]}, "disableAllHooks" => false}
      settings = File.join(project, ".claude/settings.local.json"); File.write(settings, JSON.generate(original))
      setup = ClaudeHookSetup.new(root: root, project: project)
      assert_equal 6, setup.install[:installed_events]
      merged = JSON.parse(File.read(settings))
      assert_equal original["permissions"], merged["permissions"]
      assert_equal "existing-command", merged.dig("hooks", "Stop", 0, "hooks", 0, "command")
      assert_equal 2, merged["hooks"]["Stop"].size
      assert_equal 6, setup.install[:installed_events]
      assert_equal 2, JSON.parse(File.read(settings))["hooks"]["Stop"].size
      assert Dir.glob(File.join(root, "data/private-backups/*/*settings.local.json")).any?
      panel = YAML.safe_load(File.read(File.join(root, "config/panel.yml")))
      assert_equal "data/claude-events.json", panel.dig("sources", "claude", "events_path")
      assert_equal 0, setup.uninstall[:installed_events]
      remaining = JSON.parse(File.read(settings))
      assert_equal original["permissions"], remaining["permissions"]
      assert_equal original["hooks"]["Stop"], remaining["hooks"]["Stop"]
    end
  end
end
