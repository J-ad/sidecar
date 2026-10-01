require "open3"
require "timeout"
require "fileutils"
class LocalSessionSync
  def initialize(config = PanelConfig.new, reader: nil)
    @config, @reader = config, reader
  end
  def enabled?
    enabled_sources.any? && (!Rails.env.test? || @reader)
  end
  def refresh(force: false)
    return unless enabled?
    enabled_sources.each { |source| refresh_source(source, force: force) }
  end
  private
  def enabled_sources
    %w[claude codex].select { |source| @config.settings.dig("sources", source, "automatic") == true }
  end
  def refresh_source(source, force:)
    FileUtils.mkdir_p(Rails.root.join("tmp"))
    File.open(Rails.root.join("tmp", "#{source}-sync.lock"), "w") do |lock|
      return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      state = SourceState.find_by(source: source)
      return if !force && state&.last_attempt_at && state.last_attempt_at > 60.seconds.ago
      path = @config.source_path(source)
      return unless path
      begin
        directories = @config.projects.flat_map { |p| Array(p["local_paths"]) }.uniq
        data = @reader ? @reader.call(directories) : read(source, directories)
        raise ArgumentError, "Unexpected reader output" unless data["source"] == source
      rescue StandardError => e
        data = {"version" => 1, "source" => source, "state" => "unavailable", "complete" => false,
          "observed_at" => Time.current.iso8601, "items" => [],
          "message" => "#{source.capitalize} history unavailable (#{e.class.name}); check reader installation, runtime permissions and configured project access. Previous items preserved."}
      end
      FileUtils.mkdir_p(File.dirname(path))
      temp = "#{path}.#{Process.pid}.tmp"
      File.write(temp, JSON.generate(data))
      File.rename(temp, path)
      SnapshotImporter.new(@config).import_source(source)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end
  end
  private
  def read(source, directories)
    options = @config.settings.fetch("sources").fetch(source)
    python = options["python"] || (source == "claude" ? "vendor/claude-sdk/bin/python" : "python3")
    Open3.popen3(python, Rails.root.join("scripts/read_#{source}.py").to_s, pgroup: true) do |stdin, stdout, stderr, process|
      stdin.write(JSON.generate({directories: directories, binary: options["binary"] || "codex", transport: options["transport"] || "stdio"})); stdin.close
      drain = Thread.new { stderr.read }
      begin
        output = Timeout.timeout(30) { stdout.read }
        raise ArgumentError, "SDK reader failed" unless process.value.success?
        JSON.parse(output)
      ensure
        Process.kill("TERM", -process.pid) if process.alive?
        drain.join(1)
      end
    end
  end
end
