require_relative "test_helper"
class ItemActivityTest < ActiveSupport::TestCase
  def signal(state, time: Time.current)
    {"origin" => "claude_hook", "state" => state, "observed_at" => time.iso8601, "event" => "Notification", "evidence" => "Explicit permission requested"}
  end
  test "explicit fresh approval needs user; stop means idle not task done" do
    item = row("s", "claude", facts: {"runtime_signal" => signal("waiting_approval")})
    activity = ItemActivity.for(item)
    assert activity.needs_you?
    assert_equal "Waiting for you", activity.label
    item.update!(facts: {"runtime_signal" => signal("idle"), "agent_finished" => true})
    assert_not ItemActivity.for(item).needs_you?
    assert_equal "Idle · response stopped", ItemActivity.for(item).label
    assert_nil item.facts["task_completed"]
  end
  test "history, stale lifecycle evidence and isolated runtime never invent needs-you" do
    item = row("s", "codex", facts: {"agent_finished" => true})
    assert_not ItemActivity.for(item).needs_you?
    item.update!(facts: {"runtime_signal" => signal("blocked", time: 1.hour.ago)})
    assert_equal "History only", ItemActivity.for(item).label
    item.update!(facts: {"runtime_signal" => signal("working").merge("origin" => "codex_stdio_isolated")})
    assert_equal "History only", ItemActivity.for(item).label
  end
  test "current SHA only, explicit reviewer vs others and unknown merge gates" do
    item = row("pr", "github", facts: {"bucket" => "mine", "ci" => "failure", "head_sha" => "new", "ci_sha" => "old"})
    assert_not ItemActivity.for(item).needs_you?
    item.facts["ci_sha"] = "new"; item.save!
    assert_equal "CI failed", ItemActivity.for(item).label
    item.update!(facts: {"bucket" => "review_requested"})
    assert_equal "Review this PR", ItemActivity.for(item).action
    item.update!(facts: {"bucket" => "mine", "requested_reviewers" => ["someone"]})
    assert_equal "Reviewers", ItemActivity.for(item).owner
    assert_not ItemActivity.for(item).needs_you?
    item.update!(facts: {"bucket" => "mine", "head_sha" => "new", "ci_sha" => "new", "ci" => "success", "review_decision" => "APPROVED", "review_history_checked" => true, "reviewed_sha" => "new", "conflicts" => false})
    assert_equal "Gates unverified", ItemActivity.for(item).label
    assert_not ItemActivity.for(item).needs_you?
  end
  test "current GitHub requests override prior review and resolved or closed rows stop requesting action" do
    item = row("review", "github", status: "open", facts: {"bucket" => "review_requested", "review_requested_for_viewer" => true, "viewer_review_state" => "APPROVED"})
    assert ItemActivity.for(item).needs_you? # Explicit re-request remains pending.
    item.update!(facts: item.facts.merge("review_requested_for_viewer" => false))
    assert_not ItemActivity.for(item).needs_you?
    assert_equal "Reviewed · no current request", ItemActivity.for(item).label
    assert_empty GithubSections.group([item], {item.id => ItemActivity.for(item)})["review"]
    item.update!(status: "closed", facts: {"bucket" => "mine", "ci" => "failure", "head_sha" => "new", "ci_sha" => "new"})
    assert_equal "Closed", ItemActivity.for(item).label
    assert_not ItemActivity.for(item).needs_you?
  end
  test "source failure is health info, archive hides old error, explicit followup persists" do
    item = row("pr", "github", facts: {"bucket" => "mine", "head_sha" => "new", "ci_sha" => "new", "ci" => "failure"})
    state = SourceState.create!(source: "github", state: "unavailable")
    assert_not ItemActivity.for(item, source_state: state).needs_you?
    item.update!(source: "codex", facts: {"archived" => true, "runtime_signal" => signal("blocked")})
    assert item.source_archived?
    assert_not ItemActivity.for(item).needs_you?
    item.update!(source: "github", observed_at: 1.day.ago, facts: {"merged" => true, "production_followup_required" => true})
    assert ItemActivity.for(item).needs_you?
    item.update!(followup: Item::FOLLOWUP.keys.to_h { |key| [key, {"done" => true, "evidence" => "Verified"}] })
    assert_not ItemActivity.for(item).needs_you?
  end
end
