# One subject, one check — said where it can be enforced.
#
# `has_one :validation` always meant this, and `create_validation!`
# replaces rather than adds, so the data has always agreed. Nothing said
# so to the database, and an unordered `has_one` over two rows returns
# whichever the planner reaches first: the same request could be applied
# by one machine and refused by another, and a subject whose older check
# failed could read as passed once a newer clean row existed.
#
# The rows are de-duplicated first rather than the migration being left to
# fail on deploy. Newest wins, which is what every reader already meant by
# "the validation".
class EnforceOneValidationPerSubject < ActiveRecord::Migration[8.1]
  def up
    execute(<<~SQL)
      DELETE FROM validations
      WHERE id NOT IN (
        SELECT MAX(id) FROM validations GROUP BY subject_type, subject_id
      )
    SQL

    remove_index :validations, %i[subject_type subject_id]
    add_index    :validations, %i[subject_type subject_id], unique: true
  end

  def down
    remove_index :validations, %i[subject_type subject_id]
    add_index    :validations, %i[subject_type subject_id]
  end
end
