require "json"
require "yaml"
require "fileutils"
require "shellwords"
require "rbconfig"
require "time"
class ClaudeHookSetup
  def initialize(root:, project:, ruby: RbConfig.ruby)
    @root = File.expand_path(root)
    @project = File.realpath(project)
    @ruby = ruby
    @settings_path = File.join(@project, ".claude", "settings.local.json")
    @panel_path = File.join(@root, "config", "panel.yml")
    raise ArgumentError, "Run bin/setup first" unless File.file?(@panel_path)
    raise ArgumentError, "Personal settings must not be a symlink" if File.symlink?(@settings_path) || File.symlink?(File.dirname(@settings_path))
    @panel = YAML.safe_load(File.read(@panel_path))
    paths = Array(@panel["projects"]).flat_map { |p| Array(p["local_paths"]) }
    configured = paths.any? { |path| File.directory?(path) && File.realpath(path) == @project }
    raise ArgumentError, "Configure this exact project in panel.yml local_paths first" unless configured
    @events_path = @panel.dig("sources", "claude", "events_path") || "data/claude-events.json"
    raise ArgumentError, "Events must not overwrite the SDK history snapshot" if File.expand_path(@events_path, @root) == File.expand_path(@panel.dig("sources", "claude", "path").to_s, @root)
    @command = [@ruby, File.join(@root, "bin", "claude-event"), File.expand_path(@events_path, @root)].shelljoin
  end
  def status
    settings = read_settings
    expected = hook_groups
    installed = expected.keys.count { |event| Array(settings.dig("hooks", event)).any? { |group| Array(group["hooks"]).any? { |hook| ours?(hook) } } }
    {settings_path: @settings_path, installed_events: installed, expected_events: expected.size, events_path: @events_path, hooks_disabled_locally: settings["disableAllHooks"] == true}
  end
  def install
    settings = read_settings
    settings["hooks"] ||= {}
    hook_groups.each do |event, groups|
      settings["hooks"][event] ||= []
      next if settings["hooks"][event].any? { |group| Array(group["hooks"]).any? { |hook| ours?(hook) } }
      settings["hooks"][event].concat(groups)
    end
    @panel["sources"]["claude"]["events_path"] = @events_path
    write_pair(settings)
    status
  end
  def uninstall
    settings = read_settings
    settings.fetch("hooks", {}).each_value do |groups|
      groups.each { |group| group["hooks"].reject! { |hook| ours?(hook) } }
      groups.reject! { |group| group["hooks"].empty? }
    end
    # Keep the event path and existing data: other opted-in projects may still emit events.
    write_pair(settings)
    status
  end
  private
  def read_settings
    File.file?(@settings_path) ? JSON.parse(File.read(@settings_path)) : {}
  end
  def hook_groups
    groups = JSON.parse(File.read(File.join(@root, "config", "claude-hooks.example.json"))).fetch("hooks")
    groups.each_value { |entries| entries.each { |group| group["hooks"].each { |hook| hook["command"] = @command; hook["timeout"] = 5 } } }
    groups
  end
  def ours?(hook)
    hook["type"] == "command" && hook["command"] == @command
  end
  def write_pair(settings)
    files = {@settings_path => JSON.pretty_generate(settings) + "\n", @panel_path => YAML.dump(@panel)}
    originals = files.keys.to_h { |path| [path, File.file?(path) ? File.binread(path) : nil] }
    backup = File.join(@root, "data", "private-backups", "claude-hooks-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}")
    FileUtils.mkdir_p(backup, mode: 0700)
    originals.each_with_index do |(path, bytes), index|
      File.write(File.join(backup, "#{index}-#{File.basename(path)}"), bytes, perm: 0600) if bytes
    end
    files.each do |path, bytes|
      FileUtils.mkdir_p(File.dirname(path))
      mode = File.file?(path) ? File.stat(path).mode & 0777 : 0600
      temp = "#{path}.sidecar-#{Process.pid}.tmp"
      File.write(temp, bytes, perm: mode)
      File.rename(temp, path)
    end
  end
end
