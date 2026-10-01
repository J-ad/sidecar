class SyncRevision
  def self.current
    [Item.maximum(:updated_at)&.iso8601(6), SourceState.maximum(:updated_at)&.iso8601(6), AgentQuestion.maximum(:updated_at)&.iso8601(6), Todo.maximum(:updated_at)&.iso8601(6)].join("|")
  end
end
