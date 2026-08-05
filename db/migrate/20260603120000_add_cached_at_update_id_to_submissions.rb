class AddCachedAtUpdateIdToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_reference :submissions, :cached_at_update,
                  null:        true,
                  foreign_key: {to_table: :submission_updates, on_delete: :nullify},
                  index:       {where: 'cached_at_update_id IS NOT NULL'}
  end
end
