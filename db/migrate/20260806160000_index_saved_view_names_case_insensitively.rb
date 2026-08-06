class IndexSavedViewNamesCaseInsensitively < ActiveRecord::Migration[8.1]
  # The validation reads `case_sensitive: false` and the index did not, so
  # the backstop only half worked: two concurrent saves of "BS" and "bs"
  # both passed the read-before-write check and both committed, leaving a
  # curator with two rows the model considers duplicates — after which
  # neither can be renamed without tripping the validation against the
  # other.
  # A String column list is raw SQL to `add_index`, which is what an
  # expression index needs — the Array form quotes it as an identifier and
  # Postgres refuses a column called "lower(name)".
  def up
    remove_index :saved_views, %i[user_id name] if index_exists?(:saved_views, %i[user_id name])

    add_index :saved_views, 'user_id, lower(name)', unique: true,
              name: 'index_saved_views_on_user_id_and_lower_name'
  end

  def down
    remove_index :saved_views, name: 'index_saved_views_on_user_id_and_lower_name'
    add_index    :saved_views, %i[user_id name], unique: true
  end
end
