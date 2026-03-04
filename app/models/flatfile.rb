module Flatfile
  def self.render(record)
    Root.new(record, record.sequences.entries).render
  end
end
