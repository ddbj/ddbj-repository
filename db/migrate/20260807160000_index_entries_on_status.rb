# The cross-submission accessions index exists to be filtered by status,
# and the rows it is asked for are the exceptional ones: a table of
# millions where all but a handful still hold the status they were issued
# with. Unindexed, each page of that answer is a sequential scan of the
# whole table.
#
# `id` rides along for the ordering, not for an index-only scan — the
# response needs `accession`, `entry_id`, `version` and `locus_date`, so
# every matching row is fetched from the heap either way, and a btree on
# (status, id) does not emit id order across two status values. What it
# buys is finding the handful of retracted rows without reading the
# table.
#
# Concurrently, because this runs against a table with millions of rows
# in it: a plain CREATE INDEX holds a SHARE lock for the length of the
# build, which is every accession issuance and every curator status
# change blocked until it finishes.
class IndexEntriesOnStatus < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :entries, %i[status id], algorithm: :concurrently
  end
end
