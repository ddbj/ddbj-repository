# What one accessioned row states, in the words somebody reads it in.
#
# A review link onto a set can carry any mixture of the three: a
# BioProject, a BioSample, a sequence entry. What they have in common is
# an accession and something to call it by; what they do not is
# everything else — which is why the rest travels as labelled facts
# rather than as a column per database. A reader reads them; nothing
# branches on them, and a database gaining a fact worth showing does not
# widen the payload for the other two.
#
# Only what the row itself carries. Where DDBJ has got to with it is not
# in here, for the same reason the message thread is unreachable from a
# share link.
#
# `db` is read off the submission rather than written down three times
# beside the three classes. It is the same fact — an Entry belongs to an
# ST.26 submission by construction — and saying it twice is how the two
# copies come to disagree.
AccessionFacts = Data.define(:accession, :db, :name, :details) do
  def self.for(row)
    case row
    when Project then project(row)
    when Sample  then sample(row)
    when Entry   then entry(row)
    else raise ArgumentError, "not an accessioned row: #{row.class}"
    end
  end

  def self.project(project)
    new(
      accession: project.accession,
      db:        project.submission.db,
      name:      project.title,
      details:   labelled('Type' => project.project_type)
    )
  end

  def self.sample(sample)
    new(
      accession: sample.accession,
      db:        sample.submission.db,
      name:      sample.sample_name,

      details: labelled(
        'Title'       => sample.title,
        'Organism'    => sample.organism,
        'Taxonomy ID' => sample.taxonomy_id,
        'Package'     => sample.package
      )
    )
  end

  def self.entry(entry)
    new(
      accession: entry.accession,
      db:        entry.submission.db,
      name:      entry.entry_id,

      details: labelled(
        'Version'    => entry.version,
        'LOCUS date' => entry.locus_date
      )
    )
  end

  # Blanks are dropped rather than drawn empty: a row that happens to
  # carry no organism should read as a row without one, not as a field
  # somebody forgot to fill in.
  def self.labelled(pairs)
    pairs.compact_blank.map {|label, value| {label:, value: value.to_s} }
  end
end
