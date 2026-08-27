class AddAccessionCountToRegenerateFlatfilesRuns < ActiveRecord::Migration[8.1]
  # The same rule `RegenerateFlatfilesRun.parse_numbers` applies, written
  # again in SQL because existing rows have to be counted where they are.
  #
  # Single-quoted heredoc, and the class spelled out rather than `\s`.
  # Both are load-bearing: in an interpolating heredoc Ruby turns `\s`
  # into a literal space and the pattern stops splitting on newlines,
  # and Postgres' own `\s` is `[[:space:]]`, which matches the full-width
  # space a Japanese paste is liable to contain and Ruby's `\s` does not.
  #
  # `btrim` is not a way to drop the leading empty token either: it
  # strips spaces, not newlines. Filtering the tokens is, and
  # `~ '[^[:space:]]'` is what `String#present?` means.
  #
  # DISTINCT because the form dedupes before it runs the numbers, so a
  # count that did not would disagree with what a retry of the row does.
  BACKFILL = <<~'SQL'.freeze
    UPDATE regenerate_flatfiles_runs
    SET    accession_count = (
             SELECT count(DISTINCT token)
             FROM   unnest(regexp_split_to_array(coalesce(numbers, ''), '[ \t\n\v\f\r,]+')) AS token
             WHERE  token ~ '[^[:space:]]'
           )
  SQL

  def up
    add_column :regenerate_flatfiles_runs, :accession_count, :integer, null: false, default: 0

    # Existing runs count themselves from the list they stored. The
    # progress panel is why the column exists and it is polled every three
    # seconds, so a run that predates this migration would otherwise
    # report "0 accessions" for as long as anyone looked at it.
    execute BACKFILL
  end

  def down
    remove_column :regenerate_flatfiles_runs, :accession_count
  end
end
