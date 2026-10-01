require_relative "test_helper"
require "open3"
class ClaudeEventTest < ActiveSupport::TestCase
  test "official event receiver stores response separately from task completion" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "claude.json")
      payload = {session_id: "fixture-session", hook_event_name: "Stop", cwd: "/fixture/repo", last_assistant_message: "Response finished"}
      _out, err, result = Open3.capture3(RbConfig.ruby, Rails.root.join("bin/claude-event").to_s, path, stdin_data: JSON.generate(payload))
      assert result.success?, err
      data = JSON.parse(File.read(path))
      assert_equal false, data["complete"]
      assert_equal "Official lifecycle event: Stop", data["items"][0]["evidence"]
      assert_not_includes File.read(path), "Response finished"
      assert_equal true, data["items"][0]["facts"]["agent_finished"]
      assert_nil data["items"][0]["facts"]["task_completed"]
      assert_equal "idle", data["items"][0].dig("facts", "runtime_signal", "state")
      assert data["items"][0]["observed_at"]
      payload.merge!(hook_event_name: "UserPromptSubmit")
      _out, err, result = Open3.capture3(RbConfig.ruby, Rails.root.join("bin/claude-event").to_s, path, stdin_data: JSON.generate(payload))
      assert result.success?, err
      data = JSON.parse(File.read(path))
      assert_equal 1, data["items"].size
      assert_equal false, data["items"][0]["facts"]["agent_finished"]
      payload.merge!(hook_event_name: "Notification", notification_type: "permission_prompt", message: "Permission requested")
      _out, err, result = Open3.capture3(RbConfig.ruby, Rails.root.join("bin/claude-event").to_s, path, stdin_data: JSON.generate(payload))
      assert result.success?, err
      assert_equal "waiting_approval", JSON.parse(File.read(path))["items"][0].dig("facts", "runtime_signal", "state")
    end
  end
end
