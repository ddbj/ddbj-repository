class AddVisibilityToSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :submissions, :visibility, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE submissions SET visibility = 'private';
        SQL
      end
    end

    change_column_null :submissions, :visibility, false
  end
end
