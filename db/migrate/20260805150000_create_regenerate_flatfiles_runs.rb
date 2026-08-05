class CreateRegenerateFlatfilesRuns < ActiveRecord::Migration[8.1]
  # `regenerate_flatfiles_progresses` held five counters and nothing else
  # — no actor, no scope, no failure detail — so its rows cannot be shown
  # on a screen that reports who ran what and what went wrong. They are
  # dropped rather than carried across under invented values: a row that
  # claims a scope it never recorded is worse than no row.
  def up
    drop_table :regenerate_flatfiles_progresses

    create_table :regenerate_flatfiles_runs do |t|
      t.string   :actor,  null: false
      t.string   :target, null: false
      t.text     :numbers
      t.date     :locus_date
      t.boolean  :force,       default: false, null: false
      t.integer  :total,       null: false
      t.integer  :regenerated, default: 0, null: false
      t.integer  :skipped,     default: 0, null: false
      t.integer  :failed,      default: 0, null: false
      t.datetime :started_at,  null: false
      t.datetime :finished_at
      t.references :retry_of, foreign_key: {to_table: :regenerate_flatfiles_runs}

      t.timestamps

      t.index :started_at
    end

    # One row per failure, rather than an array on the run: the jobs run
    # concurrently, and appending to a column from twenty workers at once
    # loses entries in a way a count never shows.
    create_table :regenerate_flatfiles_failures do |t|
      t.references :run, null: false, foreign_key: {to_table: :regenerate_flatfiles_runs}

      # Nullable, and nullified rather than restricted, for the two ways
      # a failure outlives its submission: one destroyed between enqueue
      # and execution (the job cannot even deserialise its arguments,
      # which is itself the failure), and one destroyed afterwards. A
      # record of what went wrong should not be what stops a submission
      # being deleted.
      t.references :submission, foreign_key: {on_delete: :nullify}

      # Stamped at the time of the failure, and required: read back
      # through the submission it would follow later renumbering — and
      # for a submission that is gone there would be nothing to read.
      t.string :label,   null: false
      t.text   :message, null: false

      t.datetime :created_at, null: false
    end
  end

  def down
    drop_table :regenerate_flatfiles_failures
    drop_table :regenerate_flatfiles_runs

    create_table :regenerate_flatfiles_progresses do |t|
      t.integer :total,     null: false
      t.integer :processed, default: 0, null: false
      t.integer :failed,    default: 0, null: false

      t.timestamps
    end
  end
end
