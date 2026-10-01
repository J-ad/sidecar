require_relative "test_helper"
class NextActionTest < ActiveSupport::TestCase
  def action(**facts)
    NextAction.for("github", {"head_sha" => "new", "ci_sha" => "new", "ci" => "success"}.merge(facts.stringify_keys))
  end
  test "old CI cannot justify current commit readiness" do
    assert_match "CI for the current", action(ci_sha: "old", ci: "success", review_history_checked: true)
  end
  test "pending review differs from request and rerequest" do
    assert_match "Wait", action(requested_reviewers: ["reviewer"])
    assert_match "Request review", action(review_history_checked: true)
    assert_match "again", action(review_history_checked: true, reviewed_sha: "old")
    assert_match "no verified", action(review_history_checked: false)
  end
  test "merge does not mark production stages done" do
    item = row("pr", "github", facts: {"merged" => true, "production_followup_required" => true}, dismissed: true)
    assert item.production_open?
    assert_match "checklist", action(merged: true)
  end
  test "malicious source links are not rendered as links" do
    item = row(source_url: "javascript:alert(1)")
    assert_nil item.safe_url
  end
end
