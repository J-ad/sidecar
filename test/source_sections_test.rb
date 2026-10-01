require_relative "test_helper"
class SourceSectionsTest < ActionDispatch::IntegrationTest
  setup { host! "127.0.0.1" }
  test "GitHub sections separate review drafts and waiting without losing other actions" do
    common = {"bucket" => "mine", "merged" => false, "draft" => false, "head_sha" => "head", "ci_sha" => "head", "ci" => "success"}
    review = row("review", "github", facts: common.merge("bucket" => "review_requested"))
    draft = row("draft", "github", facts: common.merge("draft" => true))
    waiting = row("waiting", "github", facts: common.merge("requested_reviewers" => ["reviewer"]))
    changes = row("changes", "github", facts: common.merge("review_decision" => "CHANGES_REQUESTED"))
    ci = row("ci", "github", facts: common.merge("ci" => "failure", "requested_reviewers" => ["reviewer"]))
    followup = row("followup", "github", facts: common.merge("merged" => true, "production_followup_required" => true))
    request = row("request", "github", facts: common.merge("review_history_checked" => true))
    stale = row("stale", "github", facts: common.merge("requested_reviewers" => ["reviewer"]), observed_at: 2.hours.ago)
    get root_path, params: {source: "github"}
    assert_response :success
    {"review" => [review], "drafts" => [draft], "waiting" => [waiting], "other" => [changes, ci, followup, request, stale]}.each do |group, rows|
      rows.each { |item| assert_select "[data-github-group='#{group}'] #item-#{item.id}", count: 1 }
    end
    [review, draft, waiting, changes, ci, followup, request, stale].each { |item| assert_select "#item-#{item.id}", count: 1 }
    assert_select '[data-github-group="other"] > article', count: 4
    assert_select "#item-#{stale.id} .status", text: "Status unknown"
    assert_select '#github-review-heading', text: /Review.*1/
    assert_select '#github-drafts-heading', text: /Draft PRs.*1/
    assert_select '#github-waiting-heading', text: /Waiting for review.*1/
  end
  test "requested GitHub sections have truthful empty states" do
    get root_path, params: {source: "github", q: "no-match"}
    assert_select '.github-subsection', count: 3
    assert_select '.group-empty', text: "No matching imported PRs in this section.", count: 3
    assert_select '.github-subsection .count', text: "0", count: 3
  end
  test "unknown live state does not hide the three newest imported Claude conversations" do
    rows = 5.times.map { |i| row("claude-#{i}", "claude", title: "Imported conversation #{i}", source_updated_at: i.hours.ago, facts: {"history_read" => true, "archived" => nil, "agent_finished" => nil}) }
    archived = row("archived", "claude", source_updated_at: Time.current, facts: {"archived" => true})
    get root_path, params: {source: "claude"}
    assert_response :success
    assert_select '#claude .recent-conversations article', count: 3
    rows.first(3).each { |item| assert_select "#claude .recent-conversations #item-#{item.id}", count: 1 }
    rows.drop(3).each { |item| assert_select "#claude details.history-group #item-#{item.id}", count: 1 }
    assert_select "#item-#{archived.id}", count: 0
    assert_select '#claude .recent-conversations .status', text: "Live state unknown", count: 3
    assert_select 'header p', text: /No actions confirmed yet/
  end
end
