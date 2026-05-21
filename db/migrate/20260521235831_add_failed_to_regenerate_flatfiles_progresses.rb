class AddFailedToRegenerateFlatfilesProgresses < ActiveRecord::Migration[8.1]
  def change
    add_column :regenerate_flatfiles_progresses, :failed, :integer, null: false, default: 0
  end
end
