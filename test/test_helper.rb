ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"
require "tmpdir"
class ActiveSupport::TestCase
  setup do
    Item.delete_all
    SourceState.delete_all
  end
  def row(id = "a", source = "codex", **attrs)
    Item.create!({ source: source, external_id: id, title: "Source title", observed_at: Time.current, facts: {} }.merge(attrs))
  end
end
