class CreateBioProjectSubmissions < ActiveRecord::Migration[7.1]
  def change
    change_table :submissions do |t|
      t.string :param_type
      t.string :param_id
    end

    create_table :bioproject_submission_params do |t|
      t.boolean :umbrella, null: false

      t.timestamps
    end
  end
end
