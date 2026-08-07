# Per-entry lifecycle, so a curator can cancel or withdraw one entry of a
# submission rather than the whole thing — and so the flatfile can leave
# those out.
#
# 5300 (accession_issued) for the rows already here rather than a guess
# at how far along they are: `entries.number` is NOT NULL, so an issued
# accession is the one thing provable about every one of them. It is also
# not `canceled` or `withdrawn`, which is what keeps today's flatfiles
# byte-identical.
class AddStatusToEntries < ActiveRecord::Migration[8.1]
  def change
    # The literal, not Lifecycleable::STATUSES — a migration has to write
    # what it wrote on the day it ran, whatever the constant says later.
    add_column :entries, :status, :integer, null: false, default: 5300
  end
end
