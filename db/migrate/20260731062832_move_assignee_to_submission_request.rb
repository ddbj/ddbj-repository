# Assignment is per request, not per curation row.
#
# Phase A put `assignee_id` on Project and Sample because status lives
# there, but the two are not the same shape of fact. D-way holds the
# curator (`charge_id`) on the submission and only the status per sample
# — nothing in the source data, nor in the way the work is actually
# divided, assigns individual samples to different people. Carrying it
# per row bought a "Mixed (3)" display nobody could act on, and left
# every pre-Apply request unassignable because it has no rows at all.
#
# Existing values date from Phase A only, so the backfill just lifts
# whichever assignee the rows carry (`MIN` over a set that is uniform in
# practice) up to the request.
class MoveAssigneeToSubmissionRequest < ActiveRecord::Migration[8.1]
  def up
    add_reference :submission_requests, :assignee, foreign_key: {to_table: :users}, index: true

    execute <<~SQL.squish
      UPDATE submission_requests
      SET    assignee_id = rows.assignee_id
      FROM   (
        SELECT submission_id, MIN(assignee_id) AS assignee_id
        FROM   (SELECT submission_id, assignee_id FROM projects WHERE assignee_id IS NOT NULL
                UNION ALL
                SELECT submission_id, assignee_id FROM samples  WHERE assignee_id IS NOT NULL) a
        GROUP  BY submission_id
      ) rows
      WHERE  submission_requests.submission_id = rows.submission_id
    SQL

    remove_reference :projects, :assignee, foreign_key: {to_table: :users}
    remove_reference :samples,  :assignee, foreign_key: {to_table: :users}
  end

  def down
    add_reference :projects, :assignee, foreign_key: {to_table: :users}, index: true
    add_reference :samples,  :assignee, foreign_key: {to_table: :users}, index: true

    %w[projects samples].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET    assignee_id = submission_requests.assignee_id
        FROM   submission_requests
        WHERE  submission_requests.submission_id = #{table}.submission_id
      SQL
    end

    remove_reference :submission_requests, :assignee, foreign_key: {to_table: :users}
  end
end
