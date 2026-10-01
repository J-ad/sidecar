class QuestionSuggestions
  def self.instance
    Rails.application.config.x.sidecar.question_suggestions ||= new
  end
  def initialize(broker: QuestionBroker.instance, factory: -> { HeadlessDraft.new })
    @broker, @factory = broker, factory
    @lock = Mutex.new
    @running = {}
  end
  def start(row, context: "")
    @lock.synchronize do
      row.reload
      raise ArgumentError, "Suggestions require a verified pending, non-secret question" unless @broker.routable?(row)
      return false if @running.key?(row.id)
      runner = @factory.call
      token = SecureRandom.uuid
      @running[row.id] = {runner: runner, token: token}
      row.update!(suggestion_state: "running", suggestion_answers: {}, suggestion_message: nil)
      thread = Thread.new do
        Rails.application.executor.wrap do
          begin
            answers = runner.call(row.questions, context: context)
            provider = runner.respond_to?(:provider_used) ? runner.provider_used : "test"
            fallback = runner.respond_to?(:fallback_used) && runner.fallback_used ? " (fallback)" : ""
            finish(row.id, token, "ready", answers, "Draft by #{provider}#{fallback}. Review and edit before sending.")
          rescue StandardError => e
            message = e.is_a?(HeadlessDraft::Failure) ? e.message : "Suggestion failed; no reply was sent."
            finish(row.id, token, "failed", {}, message)
          end
        end
      end
      thread.report_on_exception = false
      @running[row.id][:thread] = thread
      true
    end
  end
  def cancel(row)
    @lock.synchronize do
      operation = @running.delete(row.id)
      operation&.fetch(:runner)&.cancel
      row.update!(suggestion_state: "cancelled", suggestion_answers: {}, suggestion_message: "Cancelled. No reply was sent.")
    end
  end
  def status(row)
    @lock.synchronize do
      if row.suggestion_state == "running" && !@running.key?(row.id)
        row.update!(suggestion_state: "interrupted", suggestion_message: "Server restarted; generate again if still needed.")
      end
      if %w[running ready].include?(row.suggestion_state) && !@broker.routable?(row)
        @running.delete(row.id)&.fetch(:runner)&.cancel
        row.update!(suggestion_state: "stale", suggestion_answers: {}, suggestion_message: "Question is no longer verified pending.")
      end
      {state: row.suggestion_state, answers: row.suggestion_answers, message: row.suggestion_message}
    end
  end
  private
  def finish(id, token, state, answers, message)
    @lock.synchronize do
      return unless @running.dig(id, :token) == token
      @running.delete(id)
      row = AgentQuestion.find(id)
      if @broker.routable?(row)
        row.update!(suggestion_state: state, suggestion_answers: answers, suggestion_message: message)
      else
        row.update!(suggestion_state: "stale", suggestion_answers: {}, suggestion_message: "Question is no longer verified pending.")
      end
    end
  end
end
