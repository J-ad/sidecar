class CreateAgentQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_questions do |t|
      t.string :connection_id, :thread_id, :turn_id, :item_id, :rpc_id_json, null: false
      t.json :questions, null: false, default: []
      t.string :state, null: false, default: "pending"
      t.datetime :expires_at
      t.timestamps
    end
    add_index :agent_questions, [:connection_id, :rpc_id_json], unique: true
  end
end
