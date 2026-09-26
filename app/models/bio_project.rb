module BioProject
  # The project of a BioProject's v3 record, created if the record has none.
  # v3 holds a list of projects; a BioProject's record has exactly one.
  def self.record_project!(record)
    projects = record['projects'] = Array(record['projects']).presence || [{}]

    projects.first
  end
end
