class Item < ActiveRecord::Base
  SOURCES = %w[codex claude github].freeze
  FOLLOWUP = { "deployed" => "Deployed to production", "rake_run" => "Rake task run / not applicable", "effect_verified" => "Effect verified" }.freeze
  validates :source, inclusion: { in: SOURCES }
  validates :external_id, :title, presence: true
  validates :external_id, uniqueness: { scope: :source }

  def display(key)
    overrides.fetch(key.to_s) { public_send(key) }
  end

  def stale?(hours)
    observed_at.nil? || observed_at < hours.hours.ago || missing_from_snapshot
  end

  def source_archived?
    %w[codex claude].include?(source) && facts["archived"] == true
  end

  def hidden?
    dismissed || (snoozed_until.present? && snoozed_until.future?)
  end

  def safe_url
    uri = URI.parse(source_url.to_s)
    source_url if %w[https codex].include?(uri.scheme) && (uri.scheme == "codex" || uri.host.present?)
  rescue URI::InvalidURIError
    nil
  end

  def production_open?
    required = facts["production_followup_required"] == true || followup["required"] == true || FOLLOWUP.keys.any? { |key| followup.key?(key) }
    source == "github" && facts["merged"] == true && required && FOLLOWUP.keys.any? { |key| followup.dig(key, "done") != true }
  end
end
