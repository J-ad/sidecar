require_relative "test_helper"
class GithubSnapshotTest < ActiveSupport::TestCase
  def pr(number: 12, author: "jan", requests: [], reviews: [], state: "OPEN")
    {"number" => number, "title" => "Fixture PR", "repository" => {"nameWithOwner" => "example/app"}, "url" => "https://github.com/example/app/pull/#{number}", "state" => state, "author" => {"login" => author},
      "merged" => state == "MERGED", "headRefOid" => "new", "mergeable" => "UNKNOWN", "updatedAt" => Time.current.iso8601,
      "reviewRequests" => {"nodes" => requests.map { |login| {"requestedReviewer" => {"login" => login}} }, "pageInfo" => {"hasNextPage" => false}},
      "reviews" => {"nodes" => reviews, "pageInfo" => {"hasPreviousPage" => false}},
      "commits" => {"nodes" => [{"commit" => {"oid" => "new", "statusCheckRollup" => {"state" => "SUCCESS"}}}]}}
  end
  def review(state, time: "2026-01-01T00:00:00Z", author: "jan", sha: "new")
    {"state" => state, "submittedAt" => time, "author" => {"login" => author}, "commit" => {"oid" => sha}}
  end
  def reader(prs, discovered: prs.map { |pr| pr["number"] })
    ->(*args) do
      next({"login" => "jan"}) if args.first == "user"
      document = args.find { |arg| arg.start_with?("query=") }
      if document.include?("search(type:")
        {"data" => {"search" => {"nodes" => discovered.map { |number| {"number" => number, "repository" => {"nameWithOwner" => "example/app"}} }, "pageInfo" => {"hasNextPage" => false}}}}
      else
        requested = document.scan(/pullRequest\(number: (\d+)\)/).flatten.map(&:to_i)
        {"data" => requested.each_with_index.to_h { |number, index| ["pr#{index}", {"pullRequest" => prs.find { |pr| pr["number"] == number }}] }}
      end
    end
  end
  test "read-only discovery is scoped and details separate ownership and requests" do
    mine = pr(reviews: [review("APPROVED", author: "reviewer", sha: "old")])
    requested = pr(number: 13, author: "someone", requests: ["jan"])
    calls = []; fake = reader([mine, requested])
    result = GithubSnapshot.new(->(*args) { calls << args; fake.call(*args) }).collect(["example/app"])
    assert_equal %w[mine review_requested], result[:items].map { |r| r[:facts]["bucket"] }
    assert_equal "new", result[:items][0][:facts]["ci_sha"]
    assert_nil result[:items][0][:facts]["conflicts"]
    assert_match "again", NextAction.for("github", result[:items][0][:facts])
    assert_equal "ok", result[:state]
    assert_not result[:complete] # Complete relevant discovery isn't complete historical coverage.
    assert calls.all? { |args| %w[user graphql].include?(args.first) }
    assert calls.flatten.any? { |arg| arg == "search=repo:example/app is:pr is:open review-requested:jan" }
  end
  test "direct tracked read clears resolved request even when discovery omits it" do
    resolved = pr(author: "other", requests: ["another"], reviews: [review("APPROVED")])
    data = GithubSnapshot.new(reader([resolved], discovered: [])).collect(["example/app"], tracked: ["example/app#12"])
    facts = data[:items].first[:facts]
    assert_equal "review_resolved", facts["bucket"]
    assert_equal false, facts["review_requested_for_viewer"]
    assert_equal "APPROVED", facts["viewer_review_state"]
    assert_equal "2026-01-01T00:00:00Z", facts["viewer_review_submitted_at"]
  end
  test "comments and dismissed reviews do not invent a current request, but explicit re-request does" do
    %w[COMMENTED DISMISSED].each do |state|
      reviewed = pr(author: "other", reviews: [review(state)])
      facts = GithubSnapshot.new(reader([reviewed])).collect(["example/app"])[:items].first[:facts]
      assert_equal "review_resolved", facts["bucket"]
      assert_equal false, facts["review_requested_for_viewer"]
      assert_nil facts["reviewed_sha"]
    end
    rerequested = pr(author: "other", requests: ["jan"], reviews: [review("APPROVED")])
    facts = GithubSnapshot.new(reader([rerequested])).collect(["example/app"])[:items].first[:facts]
    assert_equal "review_requested", facts["bucket"]
    assert_equal true, facts["review_requested_for_viewer"]
  end
  test "comment after approval preserves valid approved commit, closed request is resolved" do
    reviewed = pr(author: "other", requests: ["jan"], state: "CLOSED", reviews: [review("APPROVED"), review("COMMENTED", time: "2026-01-02T00:00:00Z")])
    facts = GithubSnapshot.new(reader([reviewed])).collect(["example/app"])[:items].first[:facts]
    assert_equal "review_resolved", facts["bucket"]
    assert_equal "COMMENTED", facts["viewer_review_state"]
    assert_equal "new", facts["reviewed_sha"]
  end
  test "incomplete reviewer list cannot falsely clear prior request" do
    truncated = pr(author: "other"); truncated["reviewRequests"]["pageInfo"]["hasNextPage"] = true
    assert_raises(ArgumentError) { GithubSnapshot.new(reader([truncated])).collect(["example/app"]) }
  end
  test "rate limit response defers reads instead of claiming empty discovery" do
    fake = ->(*args) { args.first == "user" ? {"login" => "jan"} : {"errors" => [{"type" => "RATE_LIMITED"}]} }
    assert_raises(GithubSnapshot::RateLimited) { GithubSnapshot.new(fake).collect(["example/app"]) }
  end
end
