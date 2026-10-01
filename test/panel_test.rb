require_relative "test_helper"
class PanelTest < ActionDispatch::IntegrationTest
  setup do
    host! "127.0.0.1"
    @item = Item.create!(source: "github", external_id: "pr", title: "Real PR", facts: {"merged" => true, "production_followup_required" => true}, observed_at: Time.current)
  end
  test "four independent sections and persistent production checklist" do
    get root_path
    assert_response :success
    %w[codex claude github slack].each { |source| assert_select "section##{source}", count: 1 }
    assert_select "script[src='/turbo.js']"
    patch item_path(@item), params: {operation: "dismiss"}
    follow_redirect!
    assert_select "#item-#{@item.id}", count: 1
    assert @item.reload.dismissed
  end
  test "source tabs isolate one section and preserve other filters" do
    get root_path, params: {source: "github", project: "platform", q: "Real", hidden: "1"}
    assert_response :success
    assert_select 'html[lang="en"]'
    assert_select "main section", count: 1
    assert_select "section#github", count: 1
    assert_select 'nav.source-tabs a[aria-current="page"]', text: "GitHub"
    assert_select 'input[name="source"][value="github"]'
    get root_path, params: {source: "unsupported"}
    assert_select "main section", count: 4
  end
  test "each source filter shows only its section including unavailable Slack" do
    %w[codex claude github slack].each do |source|
      get root_path, params: {source: source, hidden: "1"}
      assert_response :success
      assert_select "main section", count: 1
      assert_select "section##{source}", count: 1
      assert_select 'nav.source-tabs a[aria-current="page"]', count: 1
      assert_select 'nav.source-tabs a[href*="hidden=1"]', count: 5
    end
    assert_select "#slack .empty p", text: "Slack is not connected. No threads or action status are available."
    assert_select "article", count: 0
  end
  test "hidden view shows only hidden items and tabs retain search and project" do
    @item.update!(dismissed: true)
    Item.create!(source: "codex", external_id: "visible", title: "Visible item")
    get root_path, params: {hidden: "1", source: "github", q: "Real"}
    assert_select "article", count: 1
    assert_select 'nav.source-tabs a[href*="q=Real"]', count: 5
    assert_select 'nav.source-tabs a[href*="hidden=1"]', count: 5
    get root_path, params: {q: "no-match"}
    assert_select ".empty p", text: "No items match these filters.", count: 3
  end
  test "production confirmation requires explicit evidence" do
    patch item_path(@item), params: {operation: "followup", key: "deployed", done: "1", evidence: ""}
    assert_not @item.reload.followup.dig("deployed", "done")
    patch item_path(@item), params: {operation: "followup", key: "deployed", done: "1", evidence: "Deployment log 13:00 UTC"}
    assert @item.reload.followup.dig("deployed", "done")
    assert_nil @item.followup["rake_run"]
    assert_nil @item.followup["effect_verified"]
  end
  test "correction and restore affect only local fields" do
    patch item_path(@item), params: {operation: "correct", correction: {title: "Local", status: "Do sprawdzenia", next_action: "Read source", project_id: ""}}
    assert_equal "Real PR", @item.reload.title
    assert_equal "Local", @item.display(:title)
    patch item_path(@item), params: {operation: "snooze"}
    assert @item.reload.hidden?
    patch item_path(@item), params: {operation: "restore"}
    assert_not @item.reload.hidden?
  end
  test "cross origin writes are rejected when CSRF enabled" do
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      patch item_path(@item), params: {operation: "dismiss"}, headers: {"Origin" => "https://evil.example"}
    end
    assert_not @item.reload.dismissed
  ensure
    ActionController::Base.allow_forgery_protection = old
  end
  test "source archive facts hide agent rows without confusing age, idle or local dismiss" do
    archived = row("archived", "codex", facts: {"archived" => true})
    idle = row("idle", "codex", facts: {"archived" => false, "agent_finished" => true}, source_updated_at: 1.year.ago)
    unknown = row("unknown", "claude", facts: {"archived" => nil})
    get root_path
    assert_select "#item-#{archived.id}", count: 0
    assert_select "#item-#{idle.id}", count: 1
    assert_select "#item-#{unknown.id}", count: 1
    assert_select 'button[data-copy-session="unknown"]', text: "Copy session ID"
    assert_select '.session-identity code', text: "unknown"
    idle.update!(dismissed: true)
    get root_path, params: {hidden: "1", source: "codex"}
    assert_select "#item-#{idle.id}", count: 1
    assert_select "#item-#{archived.id}", count: 0
  end
  test "revision endpoint reports local data changes without calling history readers" do
    state = SourceState.create!(source: "claude", state: "unknown", last_attempt_at: 1.hour.ago)
    attempted_at = state.last_attempt_at
      get "/sync-status"
      assert_response :success
      revision = response.parsed_body["revision"]
      @item.update!(title: "Changed")
      get "/sync-status"
      assert_not_equal revision, response.parsed_body["revision"]
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_equal attempted_at, state.reload.last_attempt_at
  end

  test "history is collapsed and only grounded actions count as needs-you" do
    @item.destroy!
    row("history", "claude", facts: {"agent_finished" => true})
    get root_path
    assert_select 'details.history-group:not([open])', count: 1
    assert_select '.group-heading', text: /Needs you/, count: 0
    assert_select 'header p', text: /No actions confirmed yet/
    assert_select '.source-details', count: 3
    assert_select '.notice.alert', count: 0
  end

  test "stale GitHub evidence warns instead of claiming no work" do
    @item.destroy!
    SourceState.create!(source: "github", state: "unknown", last_success_at: 2.hours.ago, last_attempt_at: Time.current)
    get root_path
    assert_select '.notice.alert strong', text: "Action evidence is stale"
    assert_select 'header p', text: /status coverage incomplete/
  end

end
