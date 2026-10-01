require "open3"
require "timeout"
class GithubSnapshot
  QUERY = <<~GRAPHQL
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        pullRequests(first: 100, states: [OPEN, MERGED], orderBy: {field: UPDATED_AT, direction: DESC}) {
          pageInfo { hasNextPage }
          nodes {
            number title url state updatedAt merged headRefOid isDraft mergeable reviewDecision
            author { login }
            reviewRequests(first: 100) { pageInfo { hasNextPage } nodes { requestedReviewer { ... on User { login } ... on Team { slug } } } }
            reviews(last: 100) { pageInfo { hasPreviousPage } nodes { state submittedAt commit { oid } author { login } } }
            commits(last: 1) { nodes { commit { oid statusCheckRollup { state } } } }
          }
        }
      }
    }
  GRAPHQL

  def initialize(reader = nil)
    @reader = reader || method(:read_gh)
  end

  def collect(repositories)
    raise ArgumentError, "Configure 1–5 explicit repositories" unless repositories.size.between?(1, 5)
    login = @reader.call("user").fetch("login")
    rows = repositories.flat_map do |full_name|
      raise ArgumentError, "Invalid repository mapping" unless full_name.match?(/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/)
      owner, repo = full_name.split("/")
      result = @reader.call("graphql", "-f", "query=#{QUERY}", "-F", "owner=#{owner}", "-F", "repo=#{repo}")
      raise ArgumentError, "GitHub returned errors" if result["errors"].present?
      prs = result.dig("data", "repository", "pullRequests", "nodes")
      raise ArgumentError, "Repository data unavailable" unless prs.is_a?(Array)
      prs.filter_map do |pr|
        mine = pr.dig("author", "login") == login
        requests = pr.fetch("reviewRequests")
        reviewer_names = requests.fetch("nodes").filter_map { |r| r.dig("requestedReviewer", "login") || r.dig("requestedReviewer", "slug") }
        requested = reviewer_names.include?(login)
        next unless mine || requested
        reviews = pr.fetch("reviews")
        latest_review = reviews.fetch("nodes").reverse.find { |r| %w[APPROVED CHANGES_REQUESTED].include?(r["state"]) }
        ci_commit = pr.dig("commits", "nodes", 0, "commit") || {}
        facts = {"bucket" => mine ? "mine" : "review_requested", "merged" => pr["merged"], "head_sha" => pr["headRefOid"],
          "conflicts" => {"MERGEABLE" => false, "CONFLICTING" => true}[pr["mergeable"]],
          "ci_sha" => ci_commit["oid"], "ci" => ci_commit.dig("statusCheckRollup", "state")&.downcase || "unknown",
          "requested_reviewers" => reviewer_names, "review_decision" => pr["reviewDecision"],
          "review_history_checked" => reviews.dig("pageInfo", "hasPreviousPage") == false && requests.dig("pageInfo", "hasNextPage") == false,
          "reviewed_sha" => latest_review&.dig("commit", "oid"), "draft" => pr["isDraft"]}
        {id: "#{full_name}##{pr['number']}", title: pr["title"], repository: full_name, url: pr["url"], status: pr["state"].downcase,
          updated_at: pr["updatedAt"], facts: facts, evidence: "GitHub read as #{login}; HEAD #{pr['headRefOid']}. Review decision: #{pr['reviewDecision'] || 'unknown'}."}
      end
    end
    {version: 1, source: "github", state: "unknown", complete: false, observed_at: Time.current.iso8601,
      message: "gh read for #{login}: up to 100 recently updated PRs / repo; partial coverage. Merge does not confirm production.", items: rows}
  end

  private
  def read_gh(*args)
    output, status = Timeout.timeout(30) { Open3.capture2e("gh", "api", *args) }
    raise IOError, "Read-only gh command failed (access/network)" unless status.success?
    JSON.parse(output)
  end
end
