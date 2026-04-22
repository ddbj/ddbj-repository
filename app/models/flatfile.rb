module Flatfile
  APPLICANT_NAME_FALLBACK = 'Applicants [Refer to the patent publication]'.freeze

  def self.render(record, entries)
    Root.new(record, entries).render
  end
end
