# A TSV import has two shapes of work and only one of them can be
# counted: checking is row by row, applying is a single write.
#
# `phase` lets the screen say which it is in, so "1,842 checked · 18
# rejected" gives way to "1,824 rows, one write" rather than a bar that
# claims a progress the transaction does not have. Splitting the write to
# produce that progress would cost the thing the write is for — one chain
# entry meaning "the submission now matches this TSV".
#
# `rejections` carries the first few refusals with their row number,
# column and reason, so the common case is fixable without downloading
# anything. The full set stays in `error_report`, which is also the file
# the curator corrects and uploads again.
class AddPhaseAndRejectionsToSampleTSVImports < ActiveRecord::Migration[8.1]
  def change
    add_column :sample_tsv_imports, :phase,      :string
    add_column :sample_tsv_imports, :rejections, :jsonb, null: false, default: []
  end
end
