class ReplaceDiffWithPatchOnSubmissionUpdates < ActiveRecord::Migration[8.1]
  def up
    # SubmissionUpdate has never been used in production (verified empty on
    # local, staging, and production at migration time). The destructive
    # `diff -> patch` swap is safe; we abort if rows somehow exist so we don't
    # silently drop them.
    n = ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM submission_updates').to_i

    if n.positive?
      raise "Cowardly refusing to migrate non-empty submission_updates (#{n} rows). " \
            'Hand-craft a migration that preserves data first.'
    end

    remove_column :submission_updates, :diff

    add_column :submission_updates, :actor,                   :string
    add_column :submission_updates, :source,                  :integer, null: false, default: 0
    add_column :submission_updates, :patch,                   :binary,  null: false
    add_column :submission_updates, :patch_canonical_version, :integer, null: false, default: 1

    add_check_constraint :submission_updates, 'octet_length(patch) > 0', name: 'submission_updates_patch_nonempty'

    add_index :submission_updates, :actor, where: 'actor IS NOT NULL'
    add_index :submission_updates, [:submission_id, :created_at]
  end

  def down
    # The forward path drops `diff` and stores patches in `patch`. Reverting
    # would lose every patch, so we refuse once data exists.
    n = ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM submission_updates').to_i

    raise ActiveRecord::IrreversibleMigration if n.positive?

    remove_index  :submission_updates, [:submission_id, :created_at]
    remove_index  :submission_updates, :actor

    remove_check_constraint :submission_updates, name: 'submission_updates_patch_nonempty'

    remove_column :submission_updates, :patch_canonical_version
    remove_column :submission_updates, :patch
    remove_column :submission_updates, :source
    remove_column :submission_updates, :actor

    add_column :submission_updates, :diff, :string
  end
end
