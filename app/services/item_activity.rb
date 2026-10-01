require "time"
class ItemActivity
  attr_reader :label, :action, :owner, :group, :priority, :reason
  def self.for(item, source_state: nil, now: Time.current)
    new(item, source_state: source_state, now: now)
  end
  def initialize(item, source_state:, now:)
    @item, @facts, @now = item, item.facts, now
    @label, @action, @owner, @group, @priority, @reason = "History only", "No verified action for you", "Unassigned", "history", 90, "Runtime state is unverified"
    @label = "Live state unknown" if %w[codex claude].include?(item.source) && @facts["history_read"] == true
    @label, @action, @reason = "Status unknown", "Refresh GitHub to verify the next action", "Current PR evidence is stale or unavailable" if item.source == "github"
    return if item.source_archived?
    return github if item.source == "github" && item.production_open?
    return github if item.source == "github" && item.observed_at && item.observed_at >= now - 1.hour && source_state&.state != "unavailable"
    signal = @facts["runtime_signal"]
    return unless signal.is_a?(Hash) && %w[claude_hook codex_live_server].include?(signal["origin"])
    observed = Time.iso8601(signal.fetch("observed_at")) rescue nil
    return unless observed && observed <= now + 5.minutes && observed >= now - 5.minutes
    evidence = signal["evidence"].to_s.presence || signal["event"].to_s
    case signal["state"]
    when "waiting_approval" then set("Waiting for you", "Review the requested permission in the agent", "You", "attention", 0, evidence)
    when "waiting_input" then set("Waiting for you", "Answer the agent's question", "You", "attention", 1, evidence)
    when "blocked" then set("Blocked", "Review the reported failure before continuing", "You", "attention", 2, evidence)
    when "working" then set("Working", "No action while the agent works", "Agent", "progress", 60, evidence)
    when "idle" then set("Idle · response stopped", "No verified action for you", "Unassigned", "idle", 80, evidence)
    end
  end
  def needs_you?
    group == "attention"
  end
  private
  def set(label, action, owner, group, priority, reason)
    @label, @action, @owner, @group, @priority, @reason = label, action, owner, group, priority, reason
  end
  def github
    return set("Closed", "No tracked action", "Unassigned", "history", 85, "GitHub confirms this PR is closed") if @item.status == "closed"
    if @facts["bucket"] == "review_resolved" || @facts["review_requested_for_viewer"] == false && @facts["bucket"] == "review_requested"
      label = %w[APPROVED COMMENTED CHANGES_REQUESTED].include?(@facts["viewer_review_state"]) ? "Reviewed · no current request" : "No current review request"
      return set(label, "No verified review action for you", "Unassigned", "history", 85, "GitHub current reviewer list no longer requests your review")
    end
    if @facts["merged"] == true
      if @item.production_open?
        stage = Item::FOLLOWUP.keys.find { |key| @item.followup.dig(key, "done") != true }
        set("Production follow-up", "Confirm: #{Item::FOLLOWUP.fetch(stage)}", "You", "attention", 3, "Explicit follow-up remains unverified")
      else
        set("Merged", "No tracked follow-up", "Unassigned", "history", 85, "Merge does not prove production deployment")
      end
      return
    end
    if @facts["bucket"] == "review_requested"
      return set("Review requested", "Review this PR", "You", "attention", 5, "GitHub explicitly requested your review")
    end
    return unless @facts["bucket"] == "mine"
    return set("Draft", "No verified action for you", "You", "history", 82, "PR is a draft") if @facts["draft"] == true
    return set("Blocked", "Resolve merge conflicts", "You", "attention", 2, "GitHub reports conflicts") if @facts["conflicts"] == true
    current_ci = @facts["head_sha"].present? && @facts["ci_sha"] == @facts["head_sha"]
    return set("CI failed", "Investigate current-commit CI", "You", "attention", 2, "Failing checks belong to current HEAD") if current_ci && @facts["ci"] == "failure"
    return set("Changes requested", "Address review feedback", "You", "attention", 4, "GitHub review decision requests changes") if @facts["review_decision"] == "CHANGES_REQUESTED"
    return set("Waiting for review", "No action while reviewers respond", "Reviewers", "progress", 70, "Review requests are outstanding") if @facts["requested_reviewers"].present?
    return set("Waiting for checks", "No verified action for you", "Checks", "progress", 75, "Current HEAD checks are pending or unknown") unless current_ci && @facts["ci"] == "success"
    return unless @facts["review_history_checked"] == true
    if @facts["reviewed_sha"].blank? || @facts["reviewed_sha"] != @facts["head_sha"]
      action = @facts["reviewed_sha"].blank? ? "Request review" : "Request review again for current HEAD"
      return set("Review needed", action, "You", "attention", 6, "Verified review history has no current-commit review")
    end
    if @facts["review_decision"] == "APPROVED" && @facts["conflicts"] == false && @facts["merge_gates_verified"] == true
      set("Ready to merge", "Review verified gates and merge when appropriate", "You", "attention", 7, "Explicit merge gates and current HEAD checks are verified")
    else
      set("Gates unverified", "No verified action for you", "Unassigned", "history", 86, "Approval alone does not prove merge readiness")
    end
  end
end
