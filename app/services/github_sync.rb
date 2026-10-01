require "fileutils"
class GithubSync
  POLL_SECONDS = 60
  def initialize(config = PanelConfig.new, collector: GithubSnapshot.new)
    @config, @collector = config, collector
  end
  def refresh(force: false)
    return unless force || @config.settings.dig("sources", "github", "automatic") == true
    path = @config.source_path("github")
    return unless path
    previous = read_snapshot(path)
    return if retry_pending?(previous)
    return if !force && recent_snapshot?(previous)
    File.open(Rails.root.join("tmp", "#{Rails.env}-github-sync.lock"), "w") do |lock|
      return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      previous = read_snapshot(path)
      return if retry_pending?(previous) || (!force && recent_snapshot?(previous))
      started_at = Time.current
      begin
        repos = @config.projects.flat_map { |p| Array(p["repositories"]) }.uniq
        tracked = Item.where(source: "github").select { |item| repos.include?(item.external_id.split("#").first) &&
          (item.facts["bucket"] == "review_requested" || item.production_open? || (item.facts["bucket"] == "mine" && item.status == "open")) }.map(&:external_id)
        data = @collector.collect(repos, tracked: tracked)
        data[:poll_started_at] = started_at.iso8601(6)
      rescue StandardError => e
        failures = [previous.fetch("failure_count", 0).to_i + 1, 5].min
        retry_at = e.is_a?(GithubSnapshot::RateLimited) ? e.retry_at : Time.current + [POLL_SECONDS * 2**(failures - 1), 900].min
        data = {version: 1, source: "github", state: "unavailable", complete: false, observed_at: Time.current.iso8601(6),
          next_poll_at: retry_at.iso8601, failure_count: failures,
          message: "GitHub read unavailable (#{e.class.name}); previous data preserved. Retry after #{retry_at.utc.strftime('%H:%M:%S UTC')}. No new access configured.", items: []}
      end
      FileUtils.mkdir_p(File.dirname(path))
      File.write("#{path}.#{Process.pid}.tmp", JSON.generate(data))
      File.rename("#{path}.#{Process.pid}.tmp", path)
      SnapshotImporter.new(@config).import_source("github")
    end
  end
  private
  def read_snapshot(path)
    return {} unless File.file?(path) && File.size(path) <= 5.megabytes
    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end
  def retry_pending?(data)
    data["next_poll_at"].present? && Time.iso8601(data["next_poll_at"]) > Time.current
  rescue ArgumentError
    false
  end
  def recent_snapshot?(data)
    observed = Time.iso8601(data["poll_started_at"] || data.fetch("observed_at"))
    observed > POLL_SECONDS.seconds.ago && observed <= 5.minutes.from_now
  rescue KeyError, ArgumentError
    false
  end
end
