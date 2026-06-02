class CreateProjectLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :project_links do |t|
      t.references :child_project,  null: false, foreign_key: {to_table: :projects}
      t.references :parent_project,              foreign_key: {to_table: :projects}
      t.string     :external_accession

      t.timestamps

      t.check_constraint <<~SQL.squish, name: 'project_links_target_exclusivity'
        (parent_project_id IS NOT NULL AND external_accession IS NULL)
        OR
        (parent_project_id IS NULL AND external_accession IS NOT NULL)
      SQL
    end

    add_index :project_links, [:child_project_id, :parent_project_id],
      unique: true,
      where:  'parent_project_id IS NOT NULL',
      name:   'index_project_links_on_child_and_parent'

    add_index :project_links, [:child_project_id, :external_accession],
      unique: true,
      where:  'external_accession IS NOT NULL',
      name:   'index_project_links_on_child_and_external'
  end
end
