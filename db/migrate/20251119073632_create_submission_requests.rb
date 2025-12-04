class CreateSubmissionRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :submission_requests do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :submission, null: true,  foreign_key: true

      t.integer :status, null: false, default: 0
      t.string  :error_message

      t.timestamps
    end

    create_table :submission_updates do |t|
      t.references :submission, null: false, foreign_key: true

      t.integer :status, null: false, default: 0
      t.string  :error_message

      t.timestamps
    end

    change_table :submissions do |t|
      t.remove :error_message
      t.remove :finished_at
      t.remove :param_id
      t.remove :param_type
      t.remove :progress
      t.remove :result
      t.remove :started_at
      t.remove :validation_id
      t.remove :visibility
    end

    change_table :validations do |t|
      t.references :subject, null: false, polymorphic: true

      t.remove :user_id
      t.remove :db
      t.remove :via
      t.remove :started_at
    end

    change_column_default :validations, :progress, 'running'

    change_table :validation_details do |t|
      t.references :validation, null: false, foreign_key: true

      t.string :filename

      t.remove :obj_id
    end

    drop_table :accession_renewal_validation_details
    drop_table :accession_renewals
    drop_table :objs
    drop_table :bioproject_submission_params
  end
end
