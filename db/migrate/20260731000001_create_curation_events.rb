class CreateCurationEvents < ActiveRecord::Migration[8.1]
  # Audit trail for curator actions that cannot be reduced to a patch.
  #
  # The dividing line is reducibility: an action the chain can express
  # becomes a SubmissionUpdate, so the patch chain stays a pure history of
  # the record. Status, assignee and the internal comment are not record
  # content at all. Accession IS a record field, but a volatile one —
  # `Canonicalizer.diff` strips `/**/accession` from both sides, so
  # issuance produces an empty patch and the typed column is authoritative
  # (see AccessionIssue). Both kinds of action used to leave nothing behind
  # but a bumped `updated_at`, with no actor.
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
