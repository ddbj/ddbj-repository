# What a DRA submission's publication takes with it, as D-way's did: the
# projects and samples its experiments are part of. A sample held "until
# the release of linked data" is released by nothing else.
#
# Only its own submitter's: an experiment that names someone else's
# accession — mistyped, or not — must not publish their data. D-way did
# not ask, and in its DRA about one in a hundred names another account's
# project or sample, likeliest a colleague's; those are reported for a
# curator to publish by hand rather than published here. And only
# once D-way has handed over (DwayTakeover): until then D-way releases
# what it holds, and its import would bring the status back.
module DRA::LinkedRelease
  # One numbered, private, or temporarily suppressed — as D-way's, whose
  # "ID issued" the importers bring in as `curating`. One out of the way
  # (withdrawn, canceled, permanently suppressed) stays there. Every
  # project named is taken along, where D-way took none when the
  # experiments named more than one.
  TAKEN_ALONG_FROM = %w[curating accession_issued private temporarily_suppressed].freeze

  module_function

  # Within the caller's transaction, so the DRA submission and what it
  # takes along are published together or not at all.
  def call(submission)
    return unless DwayTakeover.done?

    linked(submission.materialised_record).each do |model, accessions|
      rows     = model.joins(:submission).where(accession: accessions, status: TAKEN_ALONG_FROM)
      withheld = rows.where.not(submissions: {user_id: submission.user_id}).pluck(:accession)

      if withheld.any?
        Rails.error.report(Withheld.new("#{submission.dra_submission.accession} names #{withheld.join(', ')}, which another submitter owns"),
                           handled: true, source: 'dra.linked_release')
      end

      release rows.where(submissions: {user_id: submission.user_id}), along_with: submission
    end
  end

  # Not an error of this run: something for a curator to look at.
  class Withheld < StandardError; end

  # Each submission whose rows go is told so in its own activity feed —
  # nobody pressed anything on it.
  def release(rows, along_with:)
    counts = rows.group(:submission_id).count

    rows.move_to_status!('public')

    Submission.where(id: counts.keys).find_each do |taken|
      CurationEvent.record!(
        submission: taken,
        actor:      "system:with #{along_with.dra_submission.accession}",
        action:     :curation_updated,
        row_count:  counts.fetch(taken.id),
        noun:       taken.curation_row_noun,
        status:     'public'
      )
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
      Project => ['project', 'projects'],
      Sample  => ['sample',  'samples']
    }.filter_map {|model, (kind, list)|
      accessions = relations.select { it.dig('target', 'db') == kind }.filter_map {|relation|
        target = relation['target']

        target['accession'].presence || DDBJRecord::References.target(record, list, target)&.[]('accession')
      }

      [model, accessions.uniq] if accessions.any?
    }
  end
end
