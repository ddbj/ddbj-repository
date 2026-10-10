# What a DRA submission's publication takes with it, as D-way's did: the
# projects and samples its experiments are part of. A sample held "until
# the release of linked data" is released by nothing else.
#
# Only its own submitter's: an experiment that names someone else's
# accession — mistyped, or not — must not publish their data. And only
# for the databases taken over from D-way (HoldDateRelease.taken_over?):
# D-way releases what it still holds, and its import would bring the
# status back.
module DRA::LinkedRelease
  # One numbered, private, or temporarily suppressed — as D-way's, whose
  # "ID issued" the importers bring in as `curating`. One out of the way
  # (withdrawn, canceled, permanently suppressed) stays there.
  TAKEN_ALONG_FROM = %w[curating accession_issued private temporarily_suppressed].freeze

  module_function

  # Within the caller's transaction, so the DRA submission and what it
  # takes along are published together or not at all.
  def call(submission)
    linked(submission.materialised_record).each do |model, accessions|
      rows = model.joins(:submission).where(accession: accessions, status: TAKEN_ALONG_FROM)

      withheld = rows.where.not(submissions: {user_id: submission.user_id}).pluck(:accession)

      Rails.logger.warn "[dra] #{submission.id}: not publishing #{withheld.join(', ')}, which another submitter owns" if withheld.any?

      rows.where(submissions: {user_id: submission.user_id}).move_to_status!('public')
    end
  end

  # {Project => [accession, ...], Sample => [...]} that the record's
  # experiments are part of. A target named by alias is one the record
  # carries, and is taken along only once it has an accession of its own.
  def linked(record)
    relations = Array(record&.[]('relations')).select {|relation|
      relation['type'] == 'part_of' && relation.dig('source', 'type') == 'experiment'
    }

    {
      Project => ['project', 'projects', 'bioproject'],
      Sample  => ['sample',  'samples',  'biosample']
    }.filter_map {|model, (kind, list, db)|
      next unless HoldDateRelease.taken_over?(db)

      accessions = relations.select { it.dig('target', 'db') == kind }.filter_map {|relation|
        target = relation['target']

        target['accession'].presence || DDBJRecord::References.target(record, list, target)&.[]('accession')
      }

      [model, accessions.uniq] if accessions.any?
    }
  end
end
