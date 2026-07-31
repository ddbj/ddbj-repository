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

  def actor_label = actor.to_s.split(':', 2).last.presence || actor

  def total = issuances.size

  def done = issuances.count(&:completed?)

  def finished? = done == total

  def accession_count = issuances.sum { it.accessions.size }
end
