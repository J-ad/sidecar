class TrackSyncAttempts < ActiveRecord::Migration[8.1]
  def up
    add_column :source_states, :last_attempt_at, :datetime
    add_column :source_states, :last_success_at, :datetime
    execute "UPDATE source_states SET last_attempt_at = observed_at, last_success_at = (SELECT MAX(observed_at) FROM items WHERE items.source = source_states.source)"
  end
  def down
    remove_column :source_states, :last_attempt_at
    remove_column :source_states, :last_success_at
  end
end
