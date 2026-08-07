# `accessions` held one row per ST.26 entry — every one of its 181,754
# rows belongs to an st26 submission, and it carries `entry_id` and
# `locus_date`, neither of which means anything to BioProject or
# BioSample. Those get accessions too, on their own rows, so the general
# name was taken by the one database that could not share it.
class RenameAccessionsToEntries < ActiveRecord::Migration[8.1]
  def change
    rename_table :accessions,          :entries
    rename_table :accession_histories, :entry_histories

    # `entries.entry_id` (string) is the entry's own identifier, the word
    # the validator and `validation_details` already use for it. This is
    # the foreign key, and Postgres refuses the confusion of the two: one
    # is bigint, the other is not.
    rename_column :entry_histories, :accession_id, :entry_id
  end
end
