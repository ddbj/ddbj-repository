class AddProgressToSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :submissions, :progress,      :string, null: false, default: 'waiting'
    add_column :submissions, :result,        :string
    add_column :submissions, :error_message, :string
    add_column :submissions, :started_at,    :datetime
    add_column :submissions, :finished_at,   :datetime

    change_column_default :validations, :progress, from: nil, to: 'waiting'
  end
end
