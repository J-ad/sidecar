class PanelConfig
  attr_reader :settings
  def initialize(path = Rails.root.join("config/panel.yml"))
    @settings = YAML.safe_load(File.read(File.exist?(path) ? path : Rails.root.join("config/panel.example.yml")))
  end
  def projects
    Array(settings["projects"])
  end
  def source_path(source)
    value = settings.dig("sources", source, "path")
    Rails.root.join(value).to_s if value.present?
  end
  def project_for(row)
    return row["project_id"] if projects.any? { |p| p["id"] == row["project_id"] }
    projects.find { |p| Array(p["repositories"]).include?(row["repository"]) || Array(p["local_paths"]).include?(row["cwd"]) }&.fetch("id")
  end
  def stale_hours
    [settings.fetch("stale_after_hours", 24).to_f, 1].max
  end
  def color(project)
    value = project&.fetch("color", nil).to_s
    value.match?(/\A#[0-9a-fA-F]{6}\z/) ? value : "#64748b"
  end
end
