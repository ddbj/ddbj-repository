class SeedBpBsSequenceStarts < ActiveRecord::Migration[8.1]
  def up
    Sequence.ensure_records!

    # Idempotent: only seed when the counter is still at the initial value (1).
    # Avoids clobbering a live counter if allocate! was already invoked.
    Sequence.where(scope: 'bp', next: 1).update_all(next: 42366)
    Sequence.where(scope: 'bs', next: 1).update_all(next: 1921307)
  end

  def down
    Sequence.where(scope: %w[bp bs]).delete_all
  end
end
