# An import waiting for its job is `queued`, not `running`. The two read
# the same until the job judged a `running` row it did not hold the lock
# for to be one stopped with its process (ImportSampleTSVJob) — and an
# import merely waiting behind another would have been ended as stopped,
# then run anyway.
class QueueSampleTSVImports < ActiveRecord::Migration[8.1]
  def change
    change_column_default :sample_tsv_imports, :status, from: 'running', to: 'queued'
  end
end
