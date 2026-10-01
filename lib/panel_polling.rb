# Runs only inside bin/start's Rails process. No OS service, file-store watcher or global hook.
module PanelPolling
  def self.start
    return if @thread&.alive?
    @thread = Thread.new do
      loop do
        begin
          Rails.application.reloader.wrap do
            config = PanelConfig.new
            LocalSessionSync.new(config).refresh
            GithubSync.new(config).refresh
            SnapshotImporter.new(config).refresh
            LifecycleEvents.refresh(config)
          end
        rescue StandardError => e
          Rails.logger.warn("Sidecar polling iteration failed: #{e.class.name}")
        end
        sleep 60
      end
    end
    @thread.name = "sidecar-local-polling"
    @thread.report_on_exception = false
    at_exit { @thread&.kill }
  end
end
