# ST.26 applies that failed before 2026-10 may have been numbered: the
# numbers, the submission and its entries were committed before the rest,
# and a failure after them dropped the request's link to that submission.
# What such a request left cannot be told from one that failed before
# numbering, so it is said in its code — TRD_R0025 — rather than guessed at
# by every reader. Applying it again could number it twice
# (SubmissionRequest#reapply_blocked_reason).
#
# Running out of numbers (TRD_R0012) is the one failure known to come
# before any are taken. From here on the link is committed with the numbers,
# so a failed request without a submission was not numbered.
class MarkUnlinkedSt26Failures < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE submission_requests
      SET error_code = 'TRD_R0025'
      WHERE db = 'st26'
        AND status = 7 -- application_failed
        AND submission_id IS NULL
        AND error_code IS DISTINCT FROM 'TRD_R0012'
    SQL
  end

  def down
    # What the code was is not kept; TRD_R0025 says no less than it did.
  end
end
