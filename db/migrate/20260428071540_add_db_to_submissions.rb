class AddDbToSubmissions < ActiveRecord::Migration[8.1]
  def up
    %i[submission_requests submissions submission_updates].each do |table|
      add_column table, :db, :string
      execute "UPDATE #{table} SET db = 'st26'"
      change_column_null table, :db, false
      add_index table, :db
    end
  end

  def down
    %i[submission_requests submissions submission_updates].each do |table|
      remove_index  table, :db
      remove_column table, :db
    end
  end
end
