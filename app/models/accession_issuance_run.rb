# One press of Issue, and everything it covered.
#
# Issuance is one transaction per submission, so progress here is honest:
# "2 of 3 done" means two submissions have committed and a failure on the
# third takes nothing else with it. The run page is where that outcome
# lives — the number allocated, the range, and when the submitter was
# mailed — because a flash cannot answer a question asked next week.
class AccessionIssuanceRun < ApplicationRecord
  has_many :issuances, class_name: 'AccessionIssuance', foreign_key: :run_id, inverse_of: :run, dependent: :nullify

  validates :actor,  presence: true
  validates :origin, presence: true

  scope :recent, -> { order(started_at: :desc) }

  # What the ledger puts above the table after a press. One per curator:
  # the summary answers "what did the thing I just did actually do", so a
  # colleague's run is not it.
  scope :undismissed_for, ->(actor) { where(actor:, dismissed_at: nil).recent }

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  def total = issuances.size

  def done = issuances.count(&:completed?)

  # A row a worker died holding is believed for STALE_AFTER and no longer
  # — the same bound `AccessionIssuance.in_flight` uses to stop one
  # latching a submission shut. Without it here, the run page polls every
  # three seconds for good and the ledger's summary reads "0 of 1 done"
  # until somebody dismisses it by hand.
  def finished? = issuances.none? { it.loading? && it.started_at > AccessionIssuance::STALE_AFTER.ago }

  def accession_count = issuances.sum { it.accessions.size }

  # Changed and unchanged, as a pair. "19 accessions issued" alone cannot
  # be checked against what was ticked — the submission that quietly did
  # nothing is the one worth naming, and it is the one a count hides.
  def changed = issuances.select { it.accessions.any? }

  def unchanged = issuances.reject {|issuance| issuance.loading? || issuance.accessions.any? }

  # The mail leaves the building, so it is counted apart from the rows.
  def mailed = changed.size

  def dismissed? = dismissed_at?

  # Clears the slot, not just this row. The ledger shows one summary at a
  # time, so dismissing only this one would pop the previous press into
  # view — an older answer to a question already asked, and one the
  # curator has to dismiss again to get rid of.
  def dismiss!
    self.class
        .where(actor:, dismissed_at: nil, started_at: ..started_at)
        .update_all(dismissed_at: Time.current, updated_at: Time.current)
  end
end
