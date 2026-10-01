class CreatePanel < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :project_id
      t.string :status, null: false, default: "unknown"
      t.text :next_action
      t.string :source_url
      t.datetime :source_updated_at
      t.datetime :observed_at
      t.json :facts, default: {}
      t.text :evidence
      t.json :overrides, default: {}
      t.json :followup, default: {}
      t.datetime :snoozed_until
      t.boolean :dismissed, default: false, null: false
      t.boolean :missing_from_snapshot, default: false, null: false
      t.timestamps
    end
    add_index :items, [:source, :external_id], unique: true
    create_table :source_states do |t|
      t.string :source, null: false
      t.string :state, null: false, default: "unavailable"
      t.text :message
      t.datetime :observed_at
      t.timestamps
    end
    add_index :source_states, :source, unique: true
  end
end
