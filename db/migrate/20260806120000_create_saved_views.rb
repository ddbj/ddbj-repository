class CreateSavedViews < ActiveRecord::Migration[8.1]
  # A named ledger filter, per curator.
  #
  # There is nothing here the URL did not already carry: since the filter
  # state moved into the query string, a view is a name attached to a set
  # of params. Storing the params rather than a query is what keeps it
  # that way — a saved view can only ever mean something the screen can
  # already show.
  def change
    create_table :saved_views do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :name, null: false
      t.jsonb      :filters, null: false, default: {}

      t.timestamps
    end

    # One name per curator: two chips reading "BS to curate" is a row you
    # cannot navigate by name.
    add_index :saved_views, %i[user_id name], unique: true
  end
end
