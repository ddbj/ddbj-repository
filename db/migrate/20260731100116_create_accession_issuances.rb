# Accession issuance moves off the request cycle.
#
# `Sequence.allocate!` takes a row lock that is only released when the
# surrounding transaction commits, and since ddbj-canon/v2 that
# transaction also replays the patch chain, canonicalises it twice and
# uploads a blob. On a 100K-sample BioSample record that is tens of
# seconds — during which the curator's browser is waiting, and the
# cross-submission bulk action is about to do it again for the next
# submission, in series.
#
# Committing the allocation separately would bound the lock and burn an
# accession number every time the stamp afterwards failed. A gap in a
# published identifier space is not a trade worth making, so the lock
# stays and the wait goes somewhere nobody is sitting watching it.
#
# `targeting` records which samples were asked for, in the form the
# Samples screen expressed it: the checked ids, or the filter to
# re-derive from. Never the resolved id list for a filtered scope — that
# can be 100K entries, and re-deriving is what makes the button mean its
# label.
class CreateAccessionIssuances < ActiveRecord::Migration[8.1]
  def change
    create_table :accession_issuances do |t|
      t.references :submission, null: false, foreign_key: true, index: false

      t.string   :actor,  null: false
      t.string   :status, null: false, default: 'running'
      t.jsonb    :targeting,  null: false, default: {}
      t.jsonb    :accessions, null: false, default: []
      t.text     :error_message
      t.datetime :started_at,  null: false
      t.datetime :finished_at

      t.timestamps

      t.index %i[submission_id started_at]
    end
  end
end
