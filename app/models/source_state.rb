class SourceState < ActiveRecord::Base
  validates :source, inclusion: { in: Item::SOURCES }
end
