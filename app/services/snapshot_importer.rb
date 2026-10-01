require "json"
require "time"
class SnapshotImporter
  def initialize(config = PanelConfig.new)
    @config = config
  end

  def refresh
    Item::SOURCES.each { |source| import_source(source) }
  end

  def import_source(source)
    state = SourceState.find_or_initialize_by(source: source)
    path = @config.source_path(source)
    unless path && File.file?(path)
      state.update!(state: "unavailable", message: "No snapshot configured; existing items preserved", last_attempt_at: Time.current)
      return
    end
    raise ArgumentError, "Snapshot too large" if File.size(path) > 5.megabytes
    data = JSON.parse(File.read(path))
    raise ArgumentError, "Unsupported snapshot version" unless data["version"] == 1
    raise ArgumentError, "Wrong source" unless data["source"] == source
    raise ArgumentError, "Invalid source state" unless %w[ok unavailable unknown].include?(data["state"])
    observed = parse_time(data["observed_at"])
    raise ArgumentError, "Missing observation time" unless observed
    raise ArgumentError, "Future observation time" if observed > 5.minutes.from_now
    rows = data.fetch("items")
    raise ArgumentError, "Items must be array" unless rows.is_a?(Array) && rows.size <= 1000
    raise ArgumentError, "Unavailable snapshot cannot contain fresh items" if data["state"] == "unavailable" && rows.any?
    ids = rows.map { |row| row.fetch("id").to_s }
    raise ArgumentError, "Duplicate or empty ids" if ids.uniq != ids || ids.any?(&:blank?)
    Item.transaction do
      rows.each do |row|
        facts = row.fetch("facts", {})
        raise ArgumentError, "Invalid facts" unless facts.is_a?(Hash)
        item = Item.find_or_initialize_by(source: source, external_id: row.fetch("id").to_s)
        facts = item.facts.slice("runtime_signal").merge(facts)
        row_observed = parse_time(row["observed_at"]) || observed
        raise ArgumentError, "Future item observation" if row_observed > observed + 5.minutes
        next if item.observed_at && row_observed < item.observed_at
        item.assign_attributes(title: row.fetch("title"), project_id: @config.project_for(row), status: row.fetch("status", "unknown"),
          next_action: row["next_action"].presence || NextAction.for(source, facts), source_url: row["url"],
          source_updated_at: parse_time(row["updated_at"]), observed_at: row_observed, facts: facts,
          evidence: row["evidence"], missing_from_snapshot: false)
        item.save!
      end
      if data["state"] == "ok" && data["complete"] == true
        Item.where(source: source).where.not(external_id: ids).where("observed_at <= ?", observed).update_all(missing_from_snapshot: true)
      end
      if !state.observed_at || observed >= state.observed_at
        attrs = {state: data["state"], message: data["message"].presence || "Local snapshot · read-only", observed_at: observed, last_attempt_at: Time.current}
        attrs[:last_success_at] = observed unless data["state"] == "unavailable"
        state.update!(attrs)
      end
    end
  rescue JSON::ParserError, KeyError, ArgumentError, ActiveRecord::RecordInvalid, Errno::EACCES => e
    state.update!(state: "unavailable", message: "Snapshot could not be read (#{e.class.name}); previous data preserved", last_attempt_at: Time.current)
  end

  private
  def parse_time(value)
    Time.iso8601(value) if value.present?
  end
end
