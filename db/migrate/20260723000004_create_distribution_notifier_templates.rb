class CreateDistributionNotifierTemplates < ActiveRecord::Migration[8.1]
  # Curator-editable body/subject for the DistributionNotifier release
  # notice (DB-2005). A single row; defaults live in the model so the mail
  # works before anyone saves one.
  def change
    create_table :distribution_notifier_templates do |t|
      t.string :subject, null: false
      t.text   :body,    null: false

      t.timestamps
    end
  end
end
