require_relative "test_helper"
class QuestionSuggestionsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false
  class FakeRunner
    attr_reader :calls
    def initialize
      @queue = Queue.new; @calls = 0
    end
    def call(questions, context:)
      @calls += 1
      @queue.pop
      {questions.first.fetch("id") => "Editable draft"}
    end
    def release; @queue.push(true); end
    def cancel; release; end
  end
  setup do
    @broker = QuestionBroker.new
    @packets = []
    @connection = @broker.connect(writer: ->(packet) { @packets << packet })
    @row = @broker.ingest(@connection, {"method" => "item/tool/requestUserInput", "id" => 1, "params" => {"threadId" => "t", "turnId" => "turn", "itemId" => "i", "questions" => [{"id" => "q", "question" => "A generic question"}]}})
    @runner = FakeRunner.new
    @service = QuestionSuggestions.new(broker: @broker, factory: -> { @runner })
  end
  teardown do
    @service.cancel(@row) if @row.persisted?
    AgentQuestion.delete_all
  end
  def wait_for(state)
    Timeout.timeout(2) { sleep 0.01 until @row.reload.suggestion_state == state }
  end
  test "deduplicates generation and produces a draft without sending" do
    assert @service.start(@row)
    assert_not @service.start(@row)
    @runner.release
    wait_for("ready")
    assert_equal 1, @runner.calls
    assert_equal({"q" => "Editable draft"}, @row.suggestion_answers)
    assert_empty @packets
  end
  test "cancelled generation cannot resurrect its draft" do
    @service.start(@row)
    @service.cancel(@row)
    wait_for("cancelled")
    assert_empty @row.suggestion_answers
    assert_empty @packets
  end
  test "resolved request discards result and refuses new generation" do
    @service.start(@row)
    @broker.ingest(@connection, {"method" => "serverRequest/resolved", "params" => {"requestId" => 1, "threadId" => "t"}})
    @runner.release
    wait_for("stale")
    assert_empty @row.suggestion_answers
    assert_raises(ArgumentError) { @service.start(@row) }
    assert_empty @packets
  end
end
