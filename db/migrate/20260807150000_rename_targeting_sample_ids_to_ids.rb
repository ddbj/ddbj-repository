# `accession_issuances.targeting` stored the checkbox selection under
# `sample_ids`, from a form param of that name. The param became
# `bulk_row[ids]` when the Entries tab started sharing the screen's
# targeting, leaving the stored key as the only thing still saying
# "sample" about a mechanism that no longer only means samples.
#
# Rewritten rather than read both ways: there is one column, the rows in
# it are ours, and a shim that accepts either key is a second name kept
# alive forever to save one UPDATE.
class RenameTargetingSampleIdsToIds < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE accession_issuances
         SET targeting = (targeting - 'sample_ids') || jsonb_build_object('ids', targeting -> 'sample_ids')
       WHERE targeting ? 'sample_ids'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE accession_issuances
         SET targeting = (targeting - 'ids') || jsonb_build_object('sample_ids', targeting -> 'ids')
       WHERE targeting ? 'ids'
    SQL
  end
end
