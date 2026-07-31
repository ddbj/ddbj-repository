# One "issue accessions for this submission" attempt.
#
# Created by the controller, owned by IssueAccessionsJob, read by the
# progress page and by the request's activity feed. See the migration for
# why issuance is a job at all.
#
# Read-only from the curator's perspective: the show page polls until the
# status flips, then names the accessions that came out.
class AccessionIssuance < ApplicationRecord
  STATUSES = %w[queued running completed refused failed].freeze

  # How long a `running` row is believed. The work itself is bounded by
  # one transaction, so anything past this is a job that died with its
  # worker — and without a bound, that row would latch the submission
  # shut for good with no way to clear it but DB surgery.
  STALE_AFTER = 6.hours

  belongs_to :submission

  # `refused` is separate from `failed` because they mean opposite things
  # to the reader: refused is the service declining for a reason it can
  # state ("already has an accession"), failed is something that went
  # wrong. Rolling them together would put "this was already done" in the
  # same red box as a crash.
  enum :status, STATUSES.index_with(&:itself), suffix: :status, validate: true

  validates :actor, presence: true

  scope :recent, -> { order(started_at: :desc) }

  # Only a row a job has actually picked up, and only recently enough to
  # believe. `queued` is not running: the controller creates the row
  # before enqueueing, so counting it would let a double-click produce
  # two rows that each refuse the other and issue nothing.
  scope :running_for, ->(submission) {
    running_status.where(submission_id: submission.id, started_at: STALE_AFTER.ago..)
  }

  # The UI polls while `loading?`, and anything terminal — including a
  # refusal — stops the refresh.
  def loading? = queued_status? || running_status?

  def completed? = !loading?

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  # The curator who pressed the button, for the things that need a User
  # rather than an audit string. Nil if the account has since gone.
  def curator = User.find_by(uid: actor_label)

  # Which samples the curator asked for, as the Samples screen expressed
  # it. Resolved rather than stored so a filtered scope means what it
  # says at the time the job runs — see SampleTargeting.
  #
  # nil means "every sample in the submission", which is what the
  # workbench's own button wants. An unrecognised scope must NOT mean
  # that: widening a handful of checked rows into all 100K is the
  # irreversible direction once the Sequence has moved.
  def target_samples
    return nil unless submission.biosample_db?

    scope = targeting.with_indifferent_access

    case scope[:scope]
    when nil        then nil
    when 'selected' then submission.samples.where(id: scope[:sample_ids])
    when 'filtered' then SampleSearch.new(submission.samples, scope.fetch(:filter, {})).scope
    else                 raise Admin::SampleTargeting::UnknownScope, "Unknown target: #{scope[:scope].inspect}."
    end
  end
end
