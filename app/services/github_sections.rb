class GithubSections
  def self.group(rows, activities)
    groups = {"review" => [], "drafts" => [], "waiting" => [], "other" => []}
    rows.each do |item|
      facts = item.facts
      key = if facts["merged"] == true
        "other"
      elsif facts["bucket"] == "review_requested" && facts["review_requested_for_viewer"] != false
        "review"
      elsif facts["bucket"] == "mine" && facts["draft"] == true
        "drafts"
      elsif facts["bucket"] == "mine" && activities.fetch(item.id).label == "Waiting for review"
        "waiting"
      else
        "other"
      end
      groups.fetch(key) << item
    end
    groups
  end
end
