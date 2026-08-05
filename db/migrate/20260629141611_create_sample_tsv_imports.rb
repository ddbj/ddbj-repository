class CreateSampleTSVImports < ActiveRecord::Migration[8.1]
  def change
    create_table :sample_tsv_imports do |t|
      t.belongs_to :submission, null: false, foreign_key: true

      # 'running' | 'completed' | 'failed' — the row is created in
      # 'running' state by the controller, the job flips it to a
      # terminal state on finish.
      t.string :status, null: false, default: 'running'

      # uid of the curator who triggered the import. String to match
      # SubmissionUpdate#actor's "admin:<uid>" convention used elsewhere.
      t.string :actor, null: false

      t.integer :total,     null: false, default: 0
      t.integer :processed, null: false, default: 0
      t.integer :failed,    null: false, default: 0

      # Error rows as a re-importable TSV body (same shape as the
      # original upload). Curators can fix the cells and re-upload.
      # Sized comfortably for 100K rows × a handful of failures.
      t.text :error_report

      t.datetime :started_at,  null: false
      t.datetime :finished_at

      t.timestamps
    end
  end
end
