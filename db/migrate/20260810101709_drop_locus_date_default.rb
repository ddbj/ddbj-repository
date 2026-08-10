class DropLocusDateDefault < ActiveRecord::Migration[8.1]
  # The LOCUS date is chosen by whoever performs the publication, so a clock is
  # never the right answer for it. `ApplySubmissionRequestJob` always supplies
  # one now; leaving the default in place meant any other insert path stamped
  # today's date onto a value that gets printed on a published flatfile, with
  # nothing to say where it came from. Without the default such a path fails
  # loudly instead.
  def change
    change_column_default :entries, :locus_date, from: -> { 'CURRENT_TIMESTAMP' }, to: nil
  end
end
