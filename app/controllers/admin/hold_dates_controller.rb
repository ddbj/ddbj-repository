module Admin
  # Curator edit to v3 `submission.hold_date: str | None` (ISO YYYY-MM-DD
  # date). Goes through the patch chain via Submission#append_update! —
  # same shape as the comments / submitters edits. Empty input clears
  # the key; non-empty must parse as a strict ISO date or the save is
  # refused with a flash alert.
  class HoldDatesController < ApplicationController
    def update
      submission = Submission.find(params[:submission_id])

      raw       = params.dig(:submission, :hold_date).to_s.strip
      hold_date = parse_iso_date(raw) if raw.present?

      if raw.present? && hold_date.nil?
        return redirect_to admin_submission_path(submission),
                           alert: 'Hold date must be a valid YYYY-MM-DD date.'
      end

      new_record = patched_record(submission, hold_date)

      result = submission.append_update!(
        new_record,
        actor:  "admin:#{current_user.uid}",
        source: :manual
      )

      message = result ? "Hold date saved (chain length now #{submission.updates.count})." \
                       : 'Hold date unchanged — no patch generated.'

      redirect_to admin_submission_path(submission), notice: message
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_path(submission),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    # Strict ISO-8601 only — Date.parse would happily turn "May" or
    # "12" into a today-anchored date, silently fabricating a hold
    # value. The regex anchor rejects month-name / day-only partials
    # before Date.iso8601 even runs.
    def parse_iso_date(raw)
      return nil unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(raw).iso8601
    rescue Date::Error
      nil
    end

    def patched_record(submission, hold_date)
      record = submission.materialised_record.deep_dup
      block  = record['submission'] ||= {}

      if hold_date
        block['hold_date'] = hold_date
      else
        block.delete('hold_date')
      end

      record.delete('submission') if block.empty?
      record
    end
  end
end
