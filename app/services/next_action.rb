class NextAction
  def self.for(source, facts)
    return "Review the summary and confirm task completion" if %w[codex claude].include?(source) && facts["agent_finished"] == true
    return "Open the source and decide the next action" unless source == "github"
    return "Review the production checklist" if facts["merged"] == true
    return "Review this PR" if facts["bucket"] == "review_requested"
    return "Review the draft and decide when to request review" if facts["draft"] == true
    return "Resolve conflicts" if facts["conflicts"] == true
    return "Investigate failing CI for the current commit" if facts["ci_sha"] == facts["head_sha"] && facts["ci"] == "failure"
    return "Check CI for the current commit" if facts["head_sha"].blank? || facts["ci_sha"] != facts["head_sha"] || %w[unknown pending].include?(facts["ci"].to_s) || facts["ci"].blank?
    return "Address review feedback" if facts["review_decision"] == "CHANGES_REQUESTED"
    return "Wait for requested review" if facts["requested_reviewers"].present?
    return "Check review history — no verified read" unless facts["review_history_checked"] == true
    return "Request review again for the current commit" if facts["reviewed_sha"].present? && facts["reviewed_sha"] != facts["head_sha"]
    return "Request review" if facts["reviewed_sha"].blank?
    "Check reviews and merge readiness"
  end
end
