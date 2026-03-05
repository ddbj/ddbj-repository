module Flatfile
  def self.render(record, entries)
    Root.new(record, entries).render
  end
end
