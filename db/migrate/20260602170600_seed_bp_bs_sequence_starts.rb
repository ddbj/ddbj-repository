class SeedBpBsSequenceStarts < ActiveRecord::Migration[8.1]
  # Idempotent + safe: only advances `next` forward when the existing value
  # is behind the production floor. Never rolls counters backward, so it
  # tolerates `allocate!` running before this migration on a deployed DB.
  SEEDS = [
    {scope: 'bp', prefix: 'PRJDB', floor: 42366},
    {scope: 'bs', prefix: 'SAMD',  floor: 1921307}
  ].freeze

  def up
    SEEDS.each do |seed|
      execute <<~SQL.squish
        INSERT INTO sequences (scope, prefix, next, created_at, updated_at)
        VALUES ('#{seed[:scope]}', '#{seed[:prefix]}', #{seed[:floor]}, NOW(), NOW())
        ON CONFLICT (scope) DO UPDATE
          SET next = EXCLUDED.next
          WHERE sequences.next < EXCLUDED.next
      SQL
    end
  end

  def down
    execute "DELETE FROM sequences WHERE scope IN ('bp', 'bs')"
  end
end
