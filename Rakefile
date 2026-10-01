require_relative "config/application"
Rails.application.load_tasks
namespace :panel do
  desc "Import explicitly configured local snapshots (no remote calls)"
  task refresh: :environment do
    SnapshotImporter.new.refresh
    puts SourceState.order(:source).pluck(:source, :state, :message).map { |row| row.join(": ") }
  end
end
