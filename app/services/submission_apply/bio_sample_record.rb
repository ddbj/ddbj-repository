# A BioSample record: each sample becomes a Sample row, in the order the
# stored record holds them. Inserted in batches — a submission can hold a
# hundred thousand samples.
class SubmissionApply::BioSampleRecord < SubmissionApply::V3Record
  OWN  = 'samples'
  KIND = 'sample'

  BATCH = 5_000

  private

  def build_rows(submission, tree)
    now = Time.current

    Array(tree['samples']).each_slice(BATCH) do |samples|
      Sample.insert_all! samples.map {|sample|
        Sample.record_columns(sample).merge(
          submission_id: submission.id,
          status:        Lifecycleable::STATUSES.fetch('submission_accepted'),
          created_at:    now,
          updated_at:    now
        )
      }
    end
  end
end
