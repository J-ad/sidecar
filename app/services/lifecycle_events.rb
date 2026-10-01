require "json"
require "time"
class LifecycleEvents
  STATES = %w[waiting_approval waiting_input working idle blocked].freeze
  def self.refresh(config = PanelConfig.new)
    %w[claude codex].each do |source|
      path = config.settings.dig("sources", source, "events_path")
      next unless path.present?
      path = Rails.root.join(path)
      next unless File.file?(path)
      raise ArgumentError, "Event snapshot too large" if File.size(path) > 5.megabytes
      data = JSON.parse(File.read(path))
      raise ArgumentError, "Wrong event snapshot" unless data["version"] == 1 && data["source"] == source
      rows = data.fetch("items")
      raise ArgumentError, "Invalid event rows" unless rows.is_a?(Array) && rows.size <= 1000
      Item.transaction do
        rows.each do |row|
          signal = row.dig("facts", "runtime_signal")
          next unless signal.is_a?(Hash) && STATES.include?(signal["state"]) && %w[claude_hook codex_live_server].include?(signal["origin"])
          observed = Time.iso8601(signal.fetch("observed_at"))
          next if observed > 5.minutes.from_now
          next unless config.projects.any? { |p| Array(p["local_paths"]).include?(row["cwd"]) }
          item = Item.find_or_initialize_by(source: source, external_id: row.fetch("id"))
          prior = item.facts.dig("runtime_signal", "observed_at")
          next if prior && Time.iso8601(prior) >= observed
          item.title = row["title"].presence || "#{source.capitalize} session" if item.new_record?
          item.project_id ||= config.project_for(row)
          item.observed_at ||= observed
          item.source_updated_at ||= observed
          item.facts = item.facts.merge("runtime_signal" => signal, "task_completed" => nil)
          item.save!
        end
      end
    end
  rescue StandardError => e
    Rails.logger.warn("Lifecycle event import unavailable: #{e.class.name}")
  end
end
