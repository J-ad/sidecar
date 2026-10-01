class AddQuestionSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_questions, :suggestion_state, :string, default: "idle", null: false
    add_column :agent_questions, :suggestion_answers, :json, default: {}, null: false
    add_column :agent_questions, :suggestion_message, :string
  end
end
