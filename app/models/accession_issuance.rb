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

  # What became of the notification. Nil until the accessions commit,
  # because until then nothing has been attempted — and on a row that
  # never got that far, nil for good.
  #
  # `restricted` and `no_address` are separate from `failed` on purpose:
  # nothing went wrong, the mail simply had nowhere to go, and the four
  # are read by a curator who needs to know whether the submitter has
  # been told. Only `failed` is work left over.
  # `queued` is the honest state between `deliver_later` and the delivery
  # job settling it. Recording `sent` there was the claim this column was
  # added to stop making — the mail can still be dropped after its
  # retries, and the row went on saying it had arrived.
  MAIL_STATUSES = %w[queued sent failed restricted no_address].freeze

  # How long a `running` row is believed. The work itself is bounded by
  # one transaction, so anything past this is a job that died with its
  # worker — and without a bound, that row would latch the submission
  # shut for good with no way to clear it but DB surgery.
  STALE_AFTER = 6.hours

  belongs_to :submission
  belongs_to :run, class_name: 'AccessionIssuanceRun', optional: true

  # `refused` is separate from `failed` because they mean opposite things
  # to the reader: refused is the service declining for a reason it can
  # state ("already has an accession"), failed is something that went
  # wrong. Rolling them together would put "this was already done" in the
  # same red box as a crash.
  enum :status,      STATUSES.index_with(&:itself),      suffix: :status,      validate: true
  enum :mail_status, MAIL_STATUSES.index_with(&:itself), suffix: :mail_status, validate: {allow_nil: true}

  validates :actor, presence: true

  scope :recent, -> { order(started_at: :desc) }

  # Queued or running. While one of these exists for a submission, no
  # Issue button is offered anywhere — the ledger, the queue and the
  # workbench all read this. Pressing again before the first run commits
  # would allocate a second set of numbers, and SAMD cannot be handed
  # back.
  scope :in_flight, -> { where(status: %w[queued running], started_at: STALE_AFTER.ago..) }

  def self.in_flight_submission_ids(submission_ids)
    in_flight.where(submission_id: submission_ids).distinct.pluck(:submission_id).to_set
  end

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

  def accession_range = AccessionRange.format(accessions)

  # The curator who pressed the button, for the things that need a User
  # rather than an audit string. Nil if the account has since gone.
  def curator = User.find_by(uid: actor_label)

  # Which samples the curator asked for, as the Samples screen expressed
  # it. Resolved rather than stored so a filtered scope means what it
  # says at the time the job runs — see RowTargeting.
  #
  # `sample_ids` is the stored key and stays that way: the form param it
  # came from was renamed when the Entries tab started sharing the
  # concern, but rows written before that are still in the table, and a
  # `selected` issuance that reads the wrong key targets nothing.
  #
  # nil means "every sample in the submission", which is what the
  # workbench's own button wants. An unrecognised scope must NOT mean
  # that: widening a handful of checked rows into all 100K is the
  # irreversible direction once the Sequence has moved.
  def target_rows
    return nil unless submission.biosample_db?

    scope = targeting.with_indifferent_access

    case scope[:scope]
    when nil        then nil
    when 'selected' then submission.samples.where(id: scope[:sample_ids])
    when 'filtered' then SampleSearch.new(submission.samples, scope.fetch(:filter, {})).scope
    else                 raise Admin::RowTargeting::UnknownScope, "Unknown target: #{scope[:scope].inspect}."
    end
  end
end
