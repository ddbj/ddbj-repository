# Where a sequence took over numbering from D-way: the last number D-way had
# issued when it did (rake dra:take_over_numbering). Numbers past it are the
# repository's; D-way issuing one afterwards is a collision, and this is what
# tells one apart — `next` alone cannot, once the repository has issued past
# D-way's last.
class AddTakenOverAfterToSequences < ActiveRecord::Migration[8.1]
  def change
    add_column :sequences, :taken_over_after, :bigint
  end
end
