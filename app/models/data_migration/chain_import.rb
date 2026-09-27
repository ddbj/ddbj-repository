# frozen_string_literal: true

module DataMigration
  # How the D-way importers write what they converted into a submission's
  # patch chain — the same for every database, so said once.
  module ChainImport
    private

    # What this import writes: the conversion — except on a chain written
    # under an older ddbj-canon whose source has not changed. There the
    # import only heals the chain (one root replace under the current
    # version), and heals it with the stored record, read in the current
    # shape (Submission#materialised_record), so edits made here since the
    # last import stay. Writing the conversion would revert them.
    def record_to_write(submission, prior, record)
      submission.legacy_chain? && prior.present? && submission.same_source?(record) ? prior : record
    end

    def safe_prior_materialised(submission)
      submission.materialised_record || {}
    rescue Submission::MaterialisationFailed => e
      # A poisoned patch is a fact about THIS submission, and treating
      # its prior state as empty is how the importer heals forward.
      #
      # An unreachable store is not that fact. It makes every chain read
      # as empty, and "empty" here means "write a root snapshot built
      # from D-way" — which silently discards every curator edit the
      # chain was carrying. A store that flaps rather than stays down
      # then lets the upload succeed, and the run reports :updated.
      #
      # So it goes back up, where SyncJob stops the sweep.
      raise if StorageFailure === e

      Rails.error.report e, context: {submission_id: submission.id, source_id: submission.source_id}
      {}
    end

    # First import (empty prior) → single `add /` root snapshot, so
    # volatile fields (/schema_version, /provenance, ...) reach the
    # chain. Subsequent semantic-diff updates preserve
    # them via the diff-strips-but-apply-keeps asymmetry documented
    # on Submission#append_update!. Going through Canonicalizer.diff
    # for the empty-prior case would strip volatiles from both sides
    # — the chain would then replay to a record SMALLER than what
    # the importer's bytea cache holds, surfacing as a divergence
    # between materialised_record (cache) and materialise_at(past)
    # (pure replay) on the admin show page.
    #
    # Non-empty prior → semantic diff. The rescue catches the full
    # Canonicalizer::Error hierarchy (BagPatchPathError, now only for
    # malformed input such as a hash where the registry says bag, plus
    # ControlCharacterError / NumberGuard / SequenceCodec /
    # OrderedEmptyElement / UnsupportedValue) — those come from the
    # canonicalize pass diff() runs on BOTH sides. apply() is pure
    # RFC 6902 with no validation, so an earlier baseline can carry
    # bytes diff() rejects on re-import; falling through to a
    # root-`replace` snapshot keeps a one-off staging bug from
    # becoming a permanent :failed row.
    # Root snapshots carry the CANONICAL tree, not the raw converter
    # output. `diff` emits array indices into the canonical ordering while
    # `apply` is pure RFC 6902 against whatever is stored, so a baseline in
    # converter order leaves every later patch pointing at the wrong
    # element of a keyed array — silently, and only where the two orders
    # happen to differ. See Canonicalizer#canonical_tree.
    def compute_patch_ops(prior, current, legacy: false)
      return [{'op' => 'add', 'path' => '', 'value' => canonical(current)}] if prior.empty?

      # A pre-v2 chain stored its baseline in raw converter order, so a
      # positional diff against it would name the wrong element of a keyed
      # array. Replace the record wholesale instead — the same heal
      # Submission#append_update! performs, and needed here more: the
      # importers hold the v1 corpus, and a re-import is what runs over it.
      return [{'op' => 'replace', 'path' => '', 'value' => canonical(current)}] if legacy

      DDBJRecord::Canonicalizer.diff(prior, current)
    rescue DDBJRecord::Canonicalizer::Error
      [{'op' => 'replace', 'path' => '', 'value' => canonical(current)}]
    end

    # The rescue above fires on inputs `canonicalize` itself rejects, in
    # which case there is no canonical form to fall back to and the raw
    # tree is all we can store.
    def canonical(record)
      DDBJRecord::Canonicalizer.canonical_tree(record)
    rescue DDBJRecord::Canonicalizer::Error
      record
    end
  end
end
