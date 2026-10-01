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
    post question_reply_path(row), params: {answers: {q: "Answer"}}
    assert_response :see_other
    assert_equal "pending", row.reload.state
    row.update!(questions: [{"id" => "secret", "isSecret" => true}])
    get questions_path
    assert_select 'textarea', count: 0
    assert_select 'p', text: /Sensitive question: answer directly/
  end
end
