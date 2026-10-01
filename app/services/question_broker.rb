require "monitor"
require "securerandom"
class QuestionBroker
  def self.instance
    Rails.application.config.x.question_broker ||= new
  end
  def initialize
    @connections = {}
    @lock = Monitor.new
  end
  # Runtime integration supplies the actual owning connection's writer, never an HTTP address.
  def connect(writer:)
    @lock.synchronize do
      id = SecureRandom.uuid
      @connections[id] = {writer: writer, pending: {}}
      id
    end
  end
  def connected?
    @lock.synchronize { @connections.any? }
  end
  def ingest(connection_id, message)
    @lock.synchronize do
      connection = @connections.fetch(connection_id)
      params = message.fetch("params", {})
      case message["method"]
      when "item/tool/requestUserInput"
        request_id = message.fetch("id")
        raise ArgumentError, "Invalid RPC ID" unless request_id.is_a?(String) || request_id.is_a?(Integer)
        route = %w[threadId turnId itemId].map { |key| params.fetch(key).to_s }
        raise ArgumentError, "Missing exact route" if route.any?(&:blank?)
        questions = params.fetch("questions")
        raise ArgumentError, "Invalid question list" unless questions.is_a?(Array) && questions.size.between?(1, 3)
        ids = questions.map { |q| q.fetch("id").to_s }
        raise ArgumentError, "Invalid question IDs" unless ids.uniq == ids && ids.none?(&:blank?)
        # Secret prompt text/options are not persisted or rendered in an answer form.
        safe = questions.map do |q|
          q["isSecret"] == true ? {"id" => q["id"].to_s, "isSecret" => true} : q.slice("id", "header", "question", "options", "isOther", "isSecret")
        end
        key = JSON.generate(request_id)
        existing = AgentQuestion.find_by(connection_id: connection_id, rpc_id_json: key)
        if existing
          raise ArgumentError, "RPC ID route collision" unless [existing.thread_id, existing.turn_id, existing.item_id] == route && existing.questions == safe
          return existing
        end
        timeout = params["autoResolutionMs"]
        expiry = timeout.is_a?(Integer) && timeout >= 0 ? timeout.milliseconds.from_now : nil
        row = AgentQuestion.create!(connection_id: connection_id, rpc_id_json: key, thread_id: route[0], turn_id: route[1], item_id: route[2], questions: safe, expires_at: expiry)
        connection[:pending][row.id] = route
        row
      when "serverRequest/resolved"
        row = AgentQuestion.find_by(connection_id: connection_id, rpc_id_json: JSON.generate(params.fetch("requestId")), thread_id: params.fetch("threadId"))
        if row
          connection[:pending].delete(row.id)
          row.update!(state: "resolved")
        end
      when "turn/completed", "turn/interrupted", "thread/closed"
        connection[:pending].keys.each do |id|
          row = AgentQuestion.find(id)
          turn_id = params["turnId"] || params.dig("turn", "id")
          next unless row.thread_id == params["threadId"] && (message["method"] == "thread/closed" || (turn_id && row.turn_id == turn_id))
          row.update!(state: "stale")
          connection[:pending].delete(id)
        end
      else
        # Command/file/permission approvals and other server methods never become answer forms.
        nil
      end
    end
  end
  def routable?(row)
    @lock.synchronize do
      row.pending? && !row.secret? && @connections.dig(row.connection_id, :pending, row.id) == [row.thread_id, row.turn_id, row.item_id]
    end
  end
  def answer(row, answers)
    @lock.synchronize do
      row.reload
      raise ArgumentError, "Request resolved, expired or owning connection unavailable" unless routable?(row)
      expected = row.questions.map { |q| q.fetch("id") }
      raise ArgumentError, "Answer all question IDs exactly" unless answers.keys.sort == expected.sort
      raise ArgumentError, "Answers must be nonempty text under 5000 characters" unless answers.values.all? { |text| text.is_a?(String) && text.present? && text.length <= 5000 }
      packet = {"id" => JSON.parse(row.rpc_id_json), "result" => {"answers" => answers.to_h { |key, text| [key, {"answers" => [text]}] }}}
      begin
        @connections.fetch(row.connection_id).fetch(:writer).call(packet)
        row.update!(state: "submitted")
        @connections[row.connection_id][:pending].delete(row.id)
      rescue StandardError
        row.update!(state: "delivery_unknown")
        @connections[row.connection_id][:pending].delete(row.id)
        raise ArgumentError, "Delivery uncertain; no automatic retry. Check the original agent."
      end
    end
  end
  def disconnect(id)
    @lock.synchronize do
      @connections.delete(id)
      AgentQuestion.where(connection_id: id, state: %w[pending submitted]).update_all(state: "unavailable", updated_at: Time.current)
    end
  end
end
