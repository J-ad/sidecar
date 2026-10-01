class Todo < ActiveRecord::Base
  has_rich_text :notes
  MAX_CHECKLIST_ITEMS = 100
  validates :title, presence: true, length: { maximum: 300 }
  validates :source_link, length: { maximum: 2000 }
  validates :origin_source, inclusion: { in: Item::SOURCES }, allow_nil: true
  validate :valid_source_link
  validate :valid_project
  validate :valid_checklist
  validate :bounded_notes
  before_validation :clean_notes

  def self.from_item(item)
    new(title: item.display(:title), project_id: item.display(:project_id),
      source_link: item.safe_url, origin_source: item.source,
      origin_external_id: item.external_id, origin_title: item.display(:title), origin_url: item.safe_url)
  end

  def completed?
    completed_at.present?
  end

  def self.safe_link(value)
    uri = URI.parse(value.to_s)
    value if ((%w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.nil?) ||
      (uri.scheme == "codex" && uri.host == "threads" && uri.path.present?)) && !value.to_s.match?(/[\x00-\x20]/)
  rescue URI::InvalidURIError
    nil
  end

  def checklist_text
    checklist.map { |entry| "#{entry['done'] ? '[x] ' : ''}#{entry['label']}" }.join("\n")
  end

  def checklist_text=(text)
    previous_entries = checklist.group_by { |entry| entry["label"] }
    self.checklist = text.to_s.lines.filter_map do |line|
      label = line.strip
      next if label.blank?
      done = label.match?(/\A\[x\]\s*/i)
      label = label.sub(/\A\[(?:x| )\]\s*/i, "")
      previous = previous_entries[label]&.shift
      { "id" => previous&.fetch("id") || SecureRandom.uuid, "label" => label, "done" => done }
    end
  end

  private

  def valid_source_link
    errors.add(:source_link, "must be an HTTP(S) link or a Codex thread link") if source_link.present? && !self.class.safe_link(source_link)
  end

  def valid_project
    return if project_id.blank? || (persisted? && !will_save_change_to_project_id?)
    errors.add(:project_id, "is not configured") unless PanelConfig.new.projects.any? { |p| p["id"] == project_id }
  end

  def valid_checklist
    valid = checklist.is_a?(Array) && checklist.length <= MAX_CHECKLIST_ITEMS && checklist.all? do |entry|
      entry.is_a?(Hash) && entry["id"].is_a?(String) && entry["label"].is_a?(String) &&
        entry["label"].present? && entry["label"].length <= 300 && [true, false].include?(entry["done"])
    end
    errors.add(:checklist, "allows up to 100 tasks, each with 1–300 characters") unless valid
  end

  def bounded_notes
    errors.add(:notes, "must be at most 200 KB") if notes.body&.to_html.to_s.bytesize > 200.kilobytes
  end

  def clean_notes
    return unless notes.body
    html = ActionController::Base.helpers.sanitize(notes.body.to_html,
      tags: %w[div p br strong b em i del s blockquote pre code ul ol li a h1 action-text-attachment],
      attributes: %w[href sgid])
    fragment = Nokogiri::HTML::DocumentFragment.parse(html)
    fragment.css("action-text-attachment").each do |node|
      blob = GlobalID::Locator.locate_signed(node["sgid"], for: "attachable") rescue nil
      unless blob.is_a?(ActiveStorage::Blob) && TodoUpload.allowed_blob?(blob)
        errors.add(:notes, "contains an unsupported attachment")
        node.remove
      else
        node["url"] = Rails.application.routes.url_helpers.todo_attachment_path(blob.signed_id)
      end
    end
    self.notes = fragment.to_html unless fragment.to_html == notes.body.to_html
  end
end
