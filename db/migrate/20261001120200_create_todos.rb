class CreateTodos < ActiveRecord::Migration[8.1]
  def change
    create_table :todos do |t|
      t.string :title, null: false
      t.string :project_id
      t.string :source_link
      t.string :origin_source
      t.string :origin_external_id
      t.string :origin_title
      t.string :origin_url
      t.json :checklist, null: false, default: []
      t.datetime :completed_at
      t.timestamps
    end
    add_index :todos, :completed_at
    add_index :todos, :project_id
    add_index :todos, [:origin_source, :origin_external_id]
  end
end
