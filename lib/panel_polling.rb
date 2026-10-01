# Runs only inside bin/start's Rails process. No OS service, file-store watcher or global hook.
module PanelPolling
  def self.start
    return if @thread&.alive?
    @thread = Thread.new do
      loop do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          Rails.application.reloader.wrap do
            config = PanelConfig.new
            GithubSync.new(config).refresh
            LocalSessionSync.new(config).refresh
            SnapshotImporter.new(config).refresh
            LifecycleEvents.refresh(config)
          end
        rescue StandardError => e
          Rails.logger.warn("Sidecar polling iteration failed: #{e.class.name}")
        end
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        sleep [60 - elapsed, 1].max
      end
    end
    @thread.name = "sidecar-local-polling"
    @thread.report_on_exception = false
    at_exit { @thread&.kill }
  end
end
