class DropForceFromRegenerateFlatfilesRuns < ActiveRecord::Migration[8.1]
  # A retired option with nothing left to say. It let a run rewrite files whose
  # content had not changed, which existed because a date was applied only to
  # what the comparison had already called changed — so asking for a date
  # without it did nothing. Dates are written by accession now and a date is a
  # change like any other, so the option went; the column was kept in case its
  # `true` rows explained an old run, and there are none (production: 5 runs, 0
  # with force).
  def change
    remove_column :regenerate_flatfiles_runs, :force, :boolean, default: false, null: false
  end
end
