# Facts about an account that DDBJ Account does not hold, and that a
# curator looking someone up actually asks for.
#
# `notes` is a shared field several curators write to. Without an author
# and a date it is unattributable, which in practice means it stops being
# trusted and then stops being written.
#
# `last_signed_in_at` separates "imported from D-way and never used" from
# "was here last week" — the difference between an address worth mailing
# and one that will bounce into a void.
class AddCuratorFactsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column    :users, :notes_updated_at, :datetime
    add_reference :users, :notes_updated_by, foreign_key: {to_table: :users}, index: false

    add_column :users, :last_signed_in_at, :datetime
  end
end
