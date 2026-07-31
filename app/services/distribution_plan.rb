# What pressing Send would do, worked out before it is pressed.
#
# Mail cannot be recalled. "Send all now" asked with one line of
# `window.confirm` — which names neither how many submitters hear from us
# nor which of them will be skipped — and the per-submitter button asked
# nothing at all, which is the same outward-facing action with less
# friction on it.
#
# Grouping is the rule the notifier itself enforces (an address on file),
# so the dialog cannot promise a mail that the run then skips.
class DistributionPlan
  # One submitter's share of it. Projects rather than a count, because
  # what a curator checks before sending is which accessions are named in
  # the mail.
  Item = Data.define(:user, :projects, :skip_reason) do
    def skipped? = skip_reason.present?
  end

  def self.for(candidates, user: nil) = new(candidates, user:)

  def initialize(candidates, user: nil)
    @candidates = candidates
    @user       = user
  end

  # One item per submitter, because one mail goes to each — that is the
  # unit of the work and of the promise.
  def items
    @items ||= scoped.group_by { it.submission.user }.map {|user, projects|
      Item.new(user:, projects:, skip_reason: ('no address on file' if user.email.blank?))
    }
  end

  def sending = items.reject(&:skipped?)

  def skipped = items.select(&:skipped?)

  def mail_count = sending.size

  def project_count = sending.sum { it.projects.size }

  def any? = mail_count.positive?

  # A single-submitter send names them; the queue-wide one counts.
  def user = @user

  private

  def scoped
    @user ? @candidates.select { it.submission.user_id == @user.id } : @candidates
  end
end
