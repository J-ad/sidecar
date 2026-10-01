require_relative "test_helper"
class QuestionsTest < ActionDispatch::IntegrationTest
  setup { host! "127.0.0.1" }
  test "empty external-session inbox honestly reports no live route" do
    get questions_path
    assert_response :success
    assert_select '.notice', text: /External Desktop sessions are history-only/
    assert_select 'input[value="Send reply"]', count: 0
  end
  test "offline pending questions are visible but disabled, secret prompts hand off" do
    row = AgentQuestion.create!(connection_id: "offline", thread_id: "thread", turn_id: "turn", item_id: "item", rpc_id_json: "17", questions: [{"id" => "q", "question" => "Which approach?"}])
    get questions_path
    assert_select 'input[value="Send reply"][disabled]'
    assert_select 'button[data-generate-draft][disabled]'
    post question_suggestion_path(row), params: {context: "Generic context"}
    assert_response :unprocessable_entity
    assert_equal "idle", row.reload.suggestion_state
    post question_reply_path(row), params: {answers: {q: "Answer"}}
    assert_response :see_other
    assert_equal "pending", row.reload.state
    row.update!(questions: [{"id" => "secret", "isSecret" => true}])
    get questions_path
    assert_select 'textarea', count: 0
    assert_select '.suggestion-panel', count: 0
    assert_select 'p', text: /Sensitive question: answer directly/
  end
  test "explicit reply uses its registered owning connection once without drafting" do
    packets = []
    broker = QuestionBroker.instance
    connection = broker.connect(writer: ->(packet) { packets << packet })
    row = broker.ingest(connection, {"method" => "item/tool/requestUserInput", "id" => "route-1", "params" => {"threadId" => "thread", "turnId" => "turn", "itemId" => "item", "questions" => [{"id" => "q", "question" => "Generic choice?"}]}})
    get questions_path
    assert_select 'input[value="Send reply"]:not([disabled])', count: 1
    assert_select 'button[data-generate-draft]:not([disabled])', count: 1
    post question_reply_path(row), params: {answers: {q: "My explicit reply"}}
    assert_response :see_other
    assert_equal "submitted", row.reload.state
    assert_equal [{"id" => "route-1", "result" => {"answers" => {"q" => {"answers" => ["My explicit reply"]}}}}], packets
    post question_reply_path(row), params: {answers: {q: "Duplicate"}}
    assert_response :see_other
    assert_equal 1, packets.size
    assert_equal "idle", row.reload.suggestion_state
  ensure
    broker&.disconnect(connection) if connection
  end
end
