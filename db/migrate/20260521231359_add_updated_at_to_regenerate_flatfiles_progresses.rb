class AddUpdatedAtToRegenerateFlatfilesProgresses < ActiveRecord::Migration[8.1]
  def up
    add_column :regenerate_flatfiles_progresses, :updated_at, :datetime

    execute 'UPDATE regenerate_flatfiles_progresses SET updated_at = created_at'

    change_column_null :regenerate_flatfiles_progresses, :updated_at, false
  end

  def down
    remove_column :regenerate_flatfiles_progresses, :updated_at
  end
end
