require "fileutils"
class GithubSync
  def initialize(config = PanelConfig.new, collector: GithubSnapshot.new)
    @config, @collector = config, collector
  end
  def refresh(force: false)
    return unless force || @config.settings.dig("sources", "github", "automatic") == true
    path = @config.source_path("github")
    return unless path
    return if !force && recent_snapshot?(path)
    File.open(Rails.root.join("tmp", "#{Rails.env}-github-sync.lock"), "w") do |lock|
      return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      begin
        data = @collector.collect(@config.projects.flat_map { |p| Array(p["repositories"]) }.uniq)
      rescue StandardError => e
        data = {version: 1, source: "github", state: "unavailable", complete: false, observed_at: Time.current.iso8601,
          message: "GitHub read unavailable (#{e.class.name}); previous data preserved. No new access configured.", items: []}
      end
      FileUtils.mkdir_p(File.dirname(path))
      File.write("#{path}.#{Process.pid}.tmp", JSON.generate(data))
      File.rename("#{path}.#{Process.pid}.tmp", path)
      SnapshotImporter.new(@config).import_source("github")
    end
  end
  private
  def recent_snapshot?(path)
    return false unless File.file?(path) && File.size(path) <= 5.megabytes
    observed = Time.iso8601(JSON.parse(File.read(path)).fetch("observed_at"))
    observed > 5.minutes.ago && observed <= 5.minutes.from_now
  rescue JSON::ParserError, KeyError, ArgumentError
    false
  end

end
