class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :submission,   null: false, foreign_key: true, index: {unique: true}
      t.string     :accession
      t.integer    :project_type, null: false
      t.integer    :status,       null: false, default: 5100
      t.string     :title
      t.date       :release_date
      t.date       :hold_date
      t.date       :issued_date
      t.date       :dist_date
      t.references :assignee,     foreign_key: {to_table: :users}

      t.timestamps
    end

    add_index :projects, :accession, unique: true, where: 'accession IS NOT NULL'
    add_index :projects, :status
  end
end
