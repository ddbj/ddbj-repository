# {submission_id => [first_accession, count]} for the two databases that
# keep their accessions in a bag — BioSample samples and ST.26 entries —
# via one grouped MIN / COUNT per model.
#
# A list page prints one accession and one count per row. Without this it
# gets them by loading the bag, and a page can hold several submissions of
# 27K entries each.
module AccessionSummaries
  extend ActiveSupport::Concern

  private

  def sample_accession_summaries(submissions)
    summarise(Sample, submissions.select(&:biosample_db?).map(&:id))
      .merge(summarise(Entry, submissions.select(&:st26_db?).map(&:id)))
  end

  def summarise(model, ids)
    return {} if ids.empty?

    model
      .where(submission_id: ids)
      .group(:submission_id)
      .pluck(:submission_id, Arel.sql('MIN(accession)'), Arel.sql('COUNT(accession)'))
      .to_h {|sid, first, count| [sid, [first, count]] }
  end
end
