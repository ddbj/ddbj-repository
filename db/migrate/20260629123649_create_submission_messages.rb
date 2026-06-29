class CreateSubmissionMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :submission_messages do |t|
      t.belongs_to :submission, null: false, foreign_key: true
      t.belongs_to :user,       null: false, foreign_key: true

      # 'curator' | 'submitter'. Kept as a string rather than a boolean
      # so future actor types (system, automated) can land without a
      # schema migration.
      t.string :author_role, null: false

      t.text :body, null: false

      # Stamped when the OTHER party first observes this message:
      # for a curator-authored message that's when the submitter opens
      # the thread; for a submitter-authored message it's when any
      # curator opens the admin show page.
      t.datetime :read_at

      t.timestamps
    end

    add_index :submission_messages, %i[submission_id created_at]
    add_index :submission_messages, %i[submission_id author_role read_at]
  end
end
