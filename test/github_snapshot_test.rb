require_relative "test_helper"
class GithubSnapshotTest < ActiveSupport::TestCase
  test "read-only adapter separates ownership review requests and current SHA" do
    pr = {"number" => 12, "title" => "My PR", "url" => "https://github.com/example/app/pull/12", "state" => "OPEN", "author" => {"login" => "jan"},
      "merged" => false, "headRefOid" => "new", "mergeable" => "UNKNOWN", "updatedAt" => Time.current.iso8601,
      "reviewRequests" => {"nodes" => [], "pageInfo" => {"hasNextPage" => false}},
      "reviews" => {"nodes" => [{"state" => "APPROVED", "commit" => {"oid" => "old"}}], "pageInfo" => {"hasPreviousPage" => false}},
      "commits" => {"nodes" => [{"commit" => {"oid" => "new", "statusCheckRollup" => {"state" => "SUCCESS"}}}]}}
    reviewer = Marshal.load(Marshal.dump(pr)).merge("number" => 13, "author" => {"login" => "someone"}, "reviewRequests" => {"nodes" => [{"requestedReviewer" => {"login" => "jan"}}], "pageInfo" => {"hasNextPage" => false}})
    calls = []
    reader = ->(*args) { calls << args; args.first == "user" ? {"login" => "jan"} : {"data" => {"repository" => {"pullRequests" => {"nodes" => [pr, reviewer]}}}} }
    result = GithubSnapshot.new(reader).collect(["example/app"])
    assert_equal %w[mine review_requested], result[:items].map { |r| r[:facts]["bucket"] }
    assert_equal "new", result[:items][0][:facts]["ci_sha"]
    assert_nil result[:items][0][:facts]["conflicts"]
    assert_match "again", NextAction.for("github", result[:items][0][:facts])
    assert_not result[:complete]
    assert calls.all? { |a| %w[user graphql].include?(a.first) }
  end
end
