# One "issue accessions for this submission" attempt.
#
# Created by the controller, owned by IssueAccessionsJob, read by the
# progress page. See the migration for why issuance is a job at all.
#
# Read-only from the curator's perspective: the show page polls until the
# status flips, then names the accessions that came out.
class AccessionIssuance < ApplicationRecord
  STATUSES = %w[running completed refused failed].freeze

  belongs_to :submission

  # `refused` is separate from `failed` because they mean opposite things
  # to the reader: refused is the service declining for a reason it can
  # state ("already has an accession"), failed is something that went
  # wrong. Rolling them together would put "this was already done" in the
  # same red box as a crash.
  enum :status, STATUSES.index_with(&:itself), suffix: :status, validate: true

  validates :actor, presence: true

  scope :recent, -> { order(started_at: :desc) }

  # Mirrors SampleTSVImport: the UI polls while `loading?`, and anything
  # terminal — including a refusal — stops the refresh.
  def loading? = running_status?

  def completed? = !running_status?

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  # Which samples the curator asked for, as the Samples screen expressed
  # it. Resolved rather than stored so a filtered scope means what it
  # says at the time the job runs — see SampleTargeting.
  def target_samples
    return nil unless submission.biosample_db?

    case targeting['scope']
    when 'selected' then submission.samples.where(id: targeting['sample_ids'])
    when 'filtered' then SampleSearch.new(submission.samples, targeting.fetch('filter', {}).with_indifferent_access).scope
    end
  end
end
