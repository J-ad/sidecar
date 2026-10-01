class AgentQuestion < ActiveRecord::Base
  validates :connection_id, :thread_id, :turn_id, :item_id, :rpc_id_json, presence: true
  def secret?
    questions.any? { |question| question["isSecret"] == true }
  end
  def pending?
    state == "pending" && (!expires_at || expires_at.future?)
  end
end
