# In a table called `accessions` the column could be `number` and mean
# something. In `entries` it is a number of what — and the curation code
# that reads an accession off a row reads `accession`, which is why an
# Entry could not stand in for a Sample there.
#
# The submitter-facing API still calls the field `number` (see
# schema/openapi.yml, Accession) and keeps doing so: the view names the
# key rather than slicing the column.
class RenameEntriesNumberToAccession < ActiveRecord::Migration[8.1]
  def change
    rename_column :entries, :number, :accession
  end
end
