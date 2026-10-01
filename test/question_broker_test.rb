require_relative "test_helper"
class QuestionBrokerTest < ActiveSupport::TestCase
  setup do
    @broker = QuestionBroker.new
    @sent = []
    @connection = @broker.connect(writer: ->(packet) { @sent << packet })
  end
  def request(id: 17, turn: "turn-1", secret: false)
    {"id" => id, "method" => "item/tool/requestUserInput", "params" => {"threadId" => "thread-1", "turnId" => turn, "itemId" => "item-1", "questions" => [{"id" => "choice", "question" => "Which approach?", "isSecret" => secret}]}}
  end
  test "reply preserves exact typed RPC ID and structured answer route; no duplicate sends" do
    row = @broker.ingest(@connection, request)
    @broker.answer(row, {"choice" => "Use the smaller change"})
    assert_equal({"id" => 17, "result" => {"answers" => {"choice" => {"answers" => ["Use the smaller change"]}}}}, @sent.first)
    assert_equal "submitted", row.reload.state
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "Again"}) }
    assert_equal 1, @sent.size
    @broker.ingest(@connection, {"method" => "serverRequest/resolved", "params" => {"threadId" => "thread-1", "requestId" => 17}})
    assert_equal "resolved", row.reload.state
  end
  test "resolved, expired, changed-route, disconnected and unknown connections cannot send" do
    row = @broker.ingest(@connection, request)
    row.update!(expires_at: 1.second.ago)
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "Answer"}) }
    row.update!(expires_at: nil, turn_id: "different")
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "Answer"}) }
    row.update!(turn_id: "turn-1")
    @broker.disconnect(@connection)
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "Answer"}) }
    assert_empty @sent
  end
  test "secret text is not stored and approvals never become question forms" do
    row = @broker.ingest(@connection, request(secret: true))
    assert row.secret?
    assert_not_includes row.questions.to_json, "Which approach?"
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "SECRET"}) }
    count = AgentQuestion.count
    %w[item/permissions/requestApproval item/commandExecution/requestApproval item/fileChange/requestApproval].each do |method|
      assert_nil @broker.ingest(@connection, {"id" => 22, "method" => method, "params" => {}})
    end
    assert_equal count, AgentQuestion.count
    assert_empty @sent
  end
  test "late completion of another turn does not stale the current pending request" do
    row = @broker.ingest(@connection, request)
    @broker.ingest(@connection, {"method" => "turn/completed", "params" => {"threadId" => "thread-1", "turn" => {"id" => "old-turn"}}})
    assert @broker.routable?(row.reload)
    @broker.ingest(@connection, {"method" => "turn/completed", "params" => {"threadId" => "thread-1", "turn" => {"id" => "turn-1"}}})
    assert_equal "stale", row.reload.state
    assert_not @broker.routable?(row)
  end
  test "ambiguous delivery is not retried and ID collisions cannot reroute" do
    @broker.disconnect(@connection)
    connection = @broker.connect(writer: ->(_) { raise IOError })
    row = @broker.ingest(connection, request)
    assert_raises(ArgumentError) { @broker.ingest(connection, request(turn: "replacement")) }
    assert_raises(ArgumentError) { @broker.answer(row, {"choice" => "Answer"}) }
    assert_equal "delivery_unknown", row.reload.state
    assert_not @broker.routable?(row)
  end
  test "rejects extra, missing or blank answer IDs" do
    row = @broker.ingest(@connection, request)
    [{}, {"unknown" => "Answer"}, {"choice" => ""}, {"choice" => "Answer", "extra" => "Answer"}].each do |answers|
      assert_raises(ArgumentError) { @broker.answer(row, answers) }
    end
    assert_empty @sent
  end
end
