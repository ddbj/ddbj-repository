class RemoveDigitsFromSequences < ActiveRecord::Migration[8.1]
  def change
    remove_column :sequences, :digits, :integer, null: false
  end
end
