class CreateCurationEvents < ActiveRecord::Migration[8.1]
  # Audit trail for curator actions the DDBJ Record does not carry, and
  # which therefore have no patch to explain them.
  #
  # Status, assignee and the internal comment are operational state on
  # typed columns; the v3 record never mentions them, so before this table
  # they left nothing behind but a bumped `updated_at`, with no actor. The
  # patch chain stays a pure history of the record.
  #
  # (Accession issuance also writes an event, but as a label for the patch
  # it produces rather than in place of one — see the follow-up migration
  # that links the two.)
  #
  # Append-only, hence `created_at` without `updated_at`: an event that
  # could be edited would not be an audit trail.
  def change
    create_table :curation_events do |t|
      t.references :submission, null: false, foreign_key: true
      t.string     :action,     null: false
      t.string     :actor,      null: false

      # Rows touched — 1 project, or N samples. Kept as a column rather
      # than recomputed, because the count at the time of the action is
      # the fact being recorded.
      t.integer :row_count, null: false, default: 0

      # What changed, structured rather than pre-rendered, so the wording
      # of the activity feed stays a presentation concern.
      t.jsonb :details, null: false, default: {}

      t.datetime :created_at, null: false

      t.index [:submission_id, :created_at]
    end
  end
end
