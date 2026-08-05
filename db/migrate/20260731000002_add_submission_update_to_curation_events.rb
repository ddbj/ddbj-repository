class AddSubmissionUpdateToCurationEvents < ActiveRecord::Migration[8.1]
  # Some curator actions produce both a chain entry and an event: since
  # `ddbj-canon/v2` accession issuance patches the record (the mechanical
  # truth) *and* records what the change was in words (the label).
  #
  # Linking the two keeps the activity feed showing one line per action
  # instead of "edited the record" beside "issued 1,842 SAMD accessions".
  # Nullable, because the actions that are not record content at all —
  # status, assignee, the curator comment — have no chain entry to point
  # at, which is the whole reason CurationEvent exists.
  #
  # `nullify` rather than `cascade`: losing the patch must not erase the
  # fact that the accession was issued.
  def change
    add_reference :curation_events, :submission_update,
                  null: true, foreign_key: {on_delete: :nullify}
  end
end
