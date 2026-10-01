class PanelController < ApplicationController
  def index
    sync = LocalSessionSync.new
    sync.refresh unless ENV["WORK_PANEL_BACKGROUND"] == "1"
    @automatic_sessions = sync.enabled? || PanelConfig.new.settings.dig("sources", "github", "automatic") == true
    @revision = SyncRevision.current
    @source = Item::SOURCES.include?(params[:source]) ? params[:source] : nil
    @config = PanelConfig.new
    @states = SourceState.all.index_by(&:source)
    @items = Item.where(source: Item::SOURCES).order(source_updated_at: :desc, id: :desc).to_a
    @items.reject!(&:source_archived?)
    @items.select! { |item| item.source == @source } if @source
    @hidden_count = @items.count(&:hidden?)
    @items.select! { |item| params[:hidden] == "1" ? item.hidden? : (!item.hidden? || item.production_open?) }
    @items.select! { |item| item.display(:project_id) == params[:project] } if params[:project].present?
    @items.select! { |item| item.display(:title).to_s.downcase.include?(params[:q].to_s.downcase) } if params[:q].present?
    @activities = @items.to_h { |item| [item.id, ItemActivity.for(item, source_state: @states[item.source])] }
    @items.sort_by! { |item| [@activities[item.id].priority, -(item.source_updated_at || Time.at(0)).to_f] }
    @needs_you = @activities.values.count(&:needs_you?)
    @action_coverage_incomplete = @states.values.any? { |state| state.state == "unavailable" || state.last_success_at.nil? || (state.source == "github" && state.last_success_at < 1.hour.ago) } || @items.any? { |item| %w[codex claude].include?(item.source) && @activities[item.id].group == "history" }
  end

  def sync_status
    response.headers["Cache-Control"] = "no-store"
    render json: {revision: SyncRevision.current}
  end

  def refresh
    LocalSessionSync.new.refresh(force: true)
    GithubSync.new.refresh
    SnapshotImporter.new.refresh
    LifecycleEvents.refresh
    redirect_to root_path(params.permit(:source, :project, :q, :hidden).to_h), notice: "Configured agent histories refreshed and configured snapshots imported. No model calls.", status: :see_other
  end

  def update
    item = Item.find(params[:id])
    case params[:operation]
    when "snooze"
      item.update!(snoozed_until: 1.day.from_now)
    when "dismiss"
      item.update!(dismissed: true)
    when "restore"
      item.update!(dismissed: false, snoozed_until: nil)
    when "clear_overrides"
      item.update!(overrides: {})
    when "correct"
      overrides = params.require(:correction).permit(:title, :status, :next_action, :project_id).to_h
      raise ArgumentError, "Title cannot be blank" if overrides["title"].blank?
      raise ArgumentError, "Unknown project" if overrides["project_id"].present? && PanelConfig.new.projects.none? { |p| p["id"] == overrides["project_id"] }
      item.update!(overrides: overrides)
    when "track_followup"
      raise ArgumentError, "Only merged PRs support follow-up" unless item.source == "github" && item.facts["merged"] == true
      item.update!(followup: item.followup.merge("required" => true))
    when "followup"
      key = params.require(:key)
      raise ArgumentError, "Unknown stage" unless Item::FOLLOWUP.key?(key) && item.source == "github"
      done = params[:done] == "1"
      evidence = params[:evidence].to_s.strip
      raise ArgumentError, "Add evidence or explain why this stage is not applicable" if done && evidence.blank?
      item.update!(followup: item.followup.merge(key => { "done" => done, "evidence" => evidence, "recorded_at" => Time.current.iso8601 }))
    else
      raise ArgumentError, "Unknown operation"
    end
    redirect_to root_path(params.permit(:source, :project, :q, :hidden).to_h), notice: "Saved locally.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to root_path, alert: e.message, status: :see_other
  end
end
