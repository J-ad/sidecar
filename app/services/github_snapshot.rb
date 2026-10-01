require "open3"
require "timeout"
class GithubSnapshot
  PAGE_LIMIT = 5
  DETAIL_LIMIT = 1000
  FIELDS = <<~GRAPHQL
    number title url state updatedAt merged headRefOid isDraft mergeable reviewDecision
    repository { nameWithOwner }
    author { login }
    reviewRequests(first: 100) { pageInfo { hasNextPage } nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
    reviews(last: 20) { pageInfo { hasPreviousPage } nodes { state submittedAt commit { oid } author { login } } }
    commits(last: 1) { nodes { commit { oid statusCheckRollup { state } } } }
  GRAPHQL
  DISCOVERY = <<~GRAPHQL
    query($search: String!, $cursor: String) {
      search(type: ISSUE, query: $search, first: 100, after: $cursor) {
        issueCount pageInfo { hasNextPage endCursor }
        nodes { ... on PullRequest { number repository { nameWithOwner } } }
      }
      rateLimit { remaining resetAt }
    }
  GRAPHQL
  class RateLimited < IOError
    attr_reader :retry_at
    def initialize(retry_at = 5.minutes.from_now)
      @retry_at = retry_at
      super("GitHub rate limit; read postponed")
    end
  end

  def initialize(reader = nil)
    @reader = reader || method(:read_gh)
  end

  def collect(repositories, tracked: [])
    raise ArgumentError, "Configure 1–5 explicit repositories" unless repositories.size.between?(1, 5)
    raise ArgumentError, "Invalid repository mapping" unless repositories.all? { |repo| repo.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/) }
    @next_poll_at = nil
    login = @reader.call("user").fetch("login")
    raise ArgumentError, "Invalid GitHub login" unless login.match?(/\A[A-Za-z0-9-]+\z/)
    ids = []
    discovery_complete = true
    repositories.each do |repo|
      ["author:#{login}", "review-requested:#{login}"].each do |scope|
        cursor = nil
        more = false
        PAGE_LIMIT.times do
          result = query(DISCOVERY, {search: "repo:#{repo} is:pr is:open #{scope}", cursor: cursor}.compact)
          connection = result.fetch("search")
          connection.fetch("nodes").each { |pr| ids << "#{pr.dig('repository', 'nameWithOwner')}##{pr.fetch('number')}" }
          more = connection.dig("pageInfo", "hasNextPage")
          break unless more
          cursor = connection.dig("pageInfo", "endCursor")
          raise ArgumentError, "Missing GitHub search cursor" if cursor.blank?
        end
        discovery_complete = false if more
      end
    end
    tracked.each do |id|
      repo, number = id.split("#")
      raise ArgumentError, "Invalid tracked PR" unless repositories.include?(repo) && number.to_s.match?(/\A[1-9][0-9]*\z/)
    end
    ids = (ids + tracked).uniq
    raise ArgumentError, "Relevant PR scope exceeds bounded limit" if ids.size > DETAIL_LIMIT
    rows = ids.each_slice(20).flat_map do |batch|
      selections = batch.each_with_index.map do |id, index|
        repo, number = id.split("#"); owner, name = repo.split("/")
        "pr#{index}: repository(owner: #{JSON.generate(owner)}, name: #{JSON.generate(name)}) { pullRequest(number: #{Integer(number)}) { #{FIELDS} } }"
      end
      result = query("query { #{selections.join(' ')} rateLimit { remaining resetAt } }", {})
      batch.each_with_index.map do |_id, index|
        pr = result.dig("pr#{index}", "pullRequest")
        raise ArgumentError, "Tracked PR unavailable; prior evidence retained" unless pr.is_a?(Hash)
        build_row(pr, login)
      end
    end
    {version: 1, source: "github", state: discovery_complete ? "ok" : "unknown", complete: false, observed_at: Time.current.iso8601(6),
      next_poll_at: @next_poll_at, failure_count: 0,
      message: "GitHub read as #{login}: current authored/open and requested-review PRs, plus tracked PRs; #{discovery_complete ? 'discovery complete' : 'discovery partial (bounded search)'}. Polling every 60 seconds; merge does not confirm production.", items: rows}
  end

  private
  def query(document, variables)
    args = ["graphql", "-f", "query=#{document}"]
    variables.each { |key, value| args.concat(["-f", "#{key}=#{value}"]) }
    result = @reader.call(*args)
    if Array(result["errors"]).any? { |error| error["type"] == "RATE_LIMITED" }
      raise RateLimited
    end
    raise ArgumentError, "GitHub returned errors" if result["errors"].present?
    data = result.fetch("data")
    limit = data["rateLimit"]
    if limit && limit.fetch("remaining") < 100
      @next_poll_at = limit.fetch("resetAt")
    end
    data
  end

  def build_row(pr, login)
    mine = pr.dig("author", "login") == login
    requests = pr.fetch("reviewRequests")
    raise ArgumentError, "Review request list truncated; prior evidence retained" if requests.dig("pageInfo", "hasNextPage") != false
    reviewer_names = requests.fetch("nodes").filter_map { |r| r.dig("requestedReviewer", "login") || r.dig("requestedReviewer", "slug") }
    # Current requests override older approvals/comments, including re-requests.
    requested = pr["state"] == "OPEN" && reviewer_names.include?(login)
    reviews = pr.fetch("reviews")
    by_author = reviews.fetch("nodes").group_by { |review| review.dig("author", "login") }
    latest_by_author = by_author.values.filter_map { |rows| rows.select { |r| %w[APPROVED CHANGES_REQUESTED].include?(r["state"]) }.max_by { |r| r["submittedAt"].to_s } }
    latest_review = latest_by_author.select { |r| %w[APPROVED CHANGES_REQUESTED].include?(r["state"]) }.max_by { |r| r["submittedAt"].to_s }
    viewer_review = by_author.fetch(login, []).max_by { |r| r["submittedAt"].to_s }
    ci_commit = pr.dig("commits", "nodes", 0, "commit") || {}
    facts = {"bucket" => mine ? "mine" : requested ? "review_requested" : "review_resolved", "merged" => pr["merged"], "head_sha" => pr["headRefOid"],
      "review_requested_for_viewer" => requested, "viewer_login" => login,
      "viewer_review_state" => viewer_review&.fetch("state"), "viewer_review_submitted_at" => viewer_review&.fetch("submittedAt", nil),
      "conflicts" => {"MERGEABLE" => false, "CONFLICTING" => true}[pr["mergeable"]],
      "ci_sha" => ci_commit["oid"], "ci" => ci_commit.dig("statusCheckRollup", "state")&.downcase || "unknown",
      "requested_reviewers" => reviewer_names, "review_decision" => pr["reviewDecision"],
      "review_history_checked" => reviews.dig("pageInfo", "hasPreviousPage") == false && requests.dig("pageInfo", "hasNextPage") == false,
      "reviewed_sha" => latest_review&.dig("commit", "oid"), "draft" => pr["isDraft"]}
    {id: "#{pr.dig('repository', 'nameWithOwner')}##{pr['number']}", title: pr["title"], repository: pr.dig("repository", "nameWithOwner"), url: pr["url"], status: pr["state"].downcase,
      updated_at: pr["updatedAt"], facts: facts, evidence: "GitHub read as #{login}; HEAD #{pr['headRefOid']}. Current review request for you: #{requested ? 'yes' : 'no'}. Your latest review: #{viewer_review ? "#{viewer_review['state']} at #{viewer_review['submittedAt']}" : 'none in bounded history'}."}
  end

  def read_gh(*args)
    output, error, status = Timeout.timeout(30) { Open3.capture3("gh", "api", *args) }
    raise RateLimited if !status.success? && (error + output).match?(/rate.limit/i)
    raise IOError, "Read-only gh command failed (access/network)" unless status.success?
    JSON.parse(output)
  end
end
