class Submission < ApplicationRecord
  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :user

  has_one :request, dependent: :destroy, class_name: 'SubmissionRequest'

  has_many :updates,    dependent: :destroy, class_name: 'SubmissionUpdate'
  has_many :entries, dependent: :destroy

  has_one  :project, dependent: :destroy
  has_many :samples, dependent: :destroy

  has_many :sample_tsv_imports,  -> { recent }, dependent: :destroy
  has_many :accession_issuances, -> { recent }, dependent: :destroy

  # Curator actions that produce no patch — see CurationEvent for where
  # the line between the two histories falls.
  has_many :curation_events, -> { recent }, dependent: :destroy

  has_one_attached :ddbj_record
  has_one_attached :current_record
  has_one_attached :flatfile_na
  has_one_attached :flatfile_aa

  # Latest-materialised snapshot, blob-backed so the cumulative size
  # follows the same ceiling story as SubmissionUpdate#patch (see
  # [[project-submission-update-patch-size-ceiling]]).
  has_one_attached :cached_materialised_record

  validates :ddbj_record, attached: true, content_type: 'application/json', on: :update

  after_destroy do |submission|
    submission.dir.rmtree
  end

  def dir
    base = Rails.application.config_for(:app).repository_dir!

    Pathname.new(base).join(user.uid, 'submissions', id.to_s)
  end

  # Ensure a migration-sourced submission carries a synthetic, already-
  # applied SubmissionRequest so the request stays the single unit
  # everywhere (request-first lists + one-page detail). Idempotent: a
  # re-import finds the existing submission whose request is already
  # present and does nothing. See [[project-submission-request-as-unit]].
  def ensure_migration_request!(migration_run_id:)
    request || create_request!(
      user:             user,
      db:               db,
      status:           :applied,
      migration_run_id: migration_run_id
    )
  end

  # [first_accession, count] for list display, reading the right source
  # per DB: BP → its Project, BS → its Samples, ST.26 → its Entries. For
  # BS the caller passes the preloaded [first, count] aggregate
  # as `bs_accession` (one grouped query for the whole page) to avoid an
  # N+1; without it a BS submission reports "not loaded" (0) rather than
  # silently firing per-row queries.
  def accession_summary(bs_accession = nil)
    if bioproject_db?
      accession = project&.accession
      [accession, accession ? 1 : 0]
    elsif biosample_db?
      bs_accession || [nil, 0]
    else
      records = entries.to_a
      [records.min_by(&:id)&.number, records.size]
    end
  end

  # The rows that carry curation state (status / assignee / accession) for
  # this submission: the single BP Project, or every BS Sample. ST.26 has
  # none — it is not curated through the workbench. Returned as a relation
  # in both cases so callers can aggregate, filter and `update_all`
  # without branching on the database, which matters at 100K samples.
  def curation_rows
    if bioproject_db?
      project && Project.where(id: project.id)
    elsif biosample_db?
      samples
    end
  end

  # What a curation row is called here: BP reads "1 project", BS "1,842
  # samples". Used wherever a message has to name the thing being acted on.
  def curation_row_noun
    bioproject_db? ? 'project' : 'sample'
  end

  # True while this chain still holds a root snapshot written before
  # `ddbj-canon/v2`, i.e. in raw converter order. `diff` emits indices into
  # the canonical order, so a positional patch appended to such a chain
  # names the wrong element of a keyed array — silently, and only where the
  # two orders happen to differ.
  #
  # Every writer of the chain has to check this, not just append_update!:
  # the importers write far more of it, and they are the ones holding the
  # v1 corpus. Cleared by whichever writer heals the chain first.
  def legacy_chain?
    canonical_version < DDBJRecord::Canonicalizer::NUMBER
  end

  class MaterialisationFailed < StandardError
    attr_reader :update_id, :original

    def initialize(update_id:, original:)
      @update_id = update_id
      @original  = original
      super("SubmissionUpdate ##{update_id} replay failed: #{original.class}: #{original.message}")
    end
  end

  # Materialise the current state by replaying every SubmissionUpdate's
  # JSON Patch from {}. Returns nil if there are no updates yet.
  #
  # Caches the latest-snapshot bytes in `cached_materialised_record`
  # (ActiveStorage). Invariant: `cached_at_update_id` is non-nil iff the
  # cache is fresh — SubmissionUpdate#after_create and #after_destroy
  # (in-transaction hooks, not _commit; see submission_update.rb)
  # unconditionally nil-clear the stamp, so any chain edit (append,
  # undo, intermediate delete) invalidates. That lets the read path
  # short-circuit on column presence alone without a round trip to
  # submission_updates.
  #
  # `materialise_at(update_id:)` for historical snapshots does NOT
  # consult the cache — only the latest-state path is cached.
  def materialised_record
    if cached_at_update_id.present? && cached_materialised_record.attached?
      return Oj.load(cached_materialised_record.download, mode: :strict)
    end

    latest_id = updates.maximum(:id)
    return nil unless latest_id

    fresh = materialise_at(update_id: latest_id)
    write_through_cache(fresh, latest_id) if fresh

    fresh
  end

  # Raw cached bytes for the latest snapshot, or nil when the cache is
  # cold. Lets callers (e.g. the admin `materialised` controller) ship
  # the bytes verbatim without paying for Oj.load + re-encode.
  def cached_materialised_bytes
    return nil unless cached_at_update_id.present? && cached_materialised_record.attached?

    cached_materialised_record.download
  end

  # Replay submission_updates up to and including `update_id` (defaults
  # to the most recent). Used for `?as_of=N` historical snapshots; the
  # cache-aware fast path lives on materialised_record.
  #
  # Replay starts at the most recent root snapshot rather than at `{}`.
  # A snapshot replaces the whole document, so everything before it is
  # irrelevant to the result — and, more importantly, unreachable damage
  # before it stops mattering. That is what makes the importers' "self-heal
  # forward" a heal: a poisoned patch used to stop replay dead, and the
  # snapshot written afterwards was never reached, leaving a record that
  # only the cache could produce.
  #
  # A snapshot does not repair the *past*: `?as_of=N` for an N behind the
  # damage still fails, which is honest — that state genuinely cannot be
  # reconstructed.
  def materialise_at(update_id: nil)
    scope = updates.order(:id).with_attached_patch
    scope = scope.where('submission_updates.id <= ?', update_id) if update_id&.positive?

    if (from = scope.where(root_snapshot: true).maximum(:id))
      scope = scope.where('submission_updates.id >= ?', from)
    end

    rows = scope.to_a
    return nil if rows.empty?

    rows.reduce({}) {|state, update|
      begin
        DDBJRecord::Canonicalizer.apply(state, update.parsed_patch)
      rescue StandardError => e
        raise MaterialisationFailed.new(update_id: update.id, original: e)
      end
    }
  end

  # Compute a JSON Patch from the current materialised state to
  # `new_record`, append it as a new SubmissionUpdate, and return that
  # update. Returns nil (no-op) when the canonical diff is empty.
  #
  # Wrapped in `with_lock` so a row-level lock on the parent Submission
  # serialises concurrent appenders — without it two callers would diff
  # against the same stale base and produce a divergent chain.
  #
  # NOTE on volatile fields (canonical-json.md §4.2 asymmetry): diff
  # strips `/provenance` / `/schema_version` / etc. on BOTH sides, while
  # apply is pure RFC 6902 and leaves them intact during replay. The
  # combination means volatile keys introduced by a migration-source
  # baseline stick around — there is no append_update! path that can
  # remove them. `accession` is deliberately NOT in that set (v2): it is
  # durable state, so issuing one produces a patch like any other edit.
  def append_update!(new_record, actor:, source: :manual)
    with_lock do
      latest_id = updates.maximum(:id)
      base      = latest_id ? base_state(latest_id) : {}

      # Try a minimal semantic diff. If it lands inside a bag-mode array
      # (or any other Canonicalizer::Error — NumberGuard, ControlChar,
      # OrderedEmptyElement, etc.) fall back to a root-level snapshot.
      # That loses per-field chain granularity for THIS op but keeps
      # curator edits on bag-internal fields (e.g. submitter
      # organizations) replayable. Mirrors the same fallback used by
      # BP/BS Importer's `compute_patch_ops`.
      patch =
        if heal_chain?(base)
          [{'op' => 'replace', 'path' => '', 'value' => snapshot_value(new_record)}]
        else
          begin
            DDBJRecord::Canonicalizer.diff(base, new_record)
          rescue DDBJRecord::Canonicalizer::Error
            [{'op' => (base.empty? ? 'add' : 'replace'), 'path' => '', 'value' => snapshot_value(new_record)}]
          end
        end

      return nil if patch.empty?

      update = SubmissionUpdate.create_with_patch!(
        submission:              self,
        patch_json:              Oj.dump(patch, mode: :strict),
        db:                      db,
        status:                  :applied,
        actor:                   actor,
        source:                  source,
        patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
      )

      # The chain is canonical from here on, whether it already was or was
      # just healed above.
      update_columns(canonical_version: DDBJRecord::Canonicalizer::NUMBER)

      update
      # Cache invalidates via SubmissionUpdate#after_create (inside this
      # transaction) — no explicit clear here. Deliberately bypassing the
      # cached read (using materialise_at directly) because we are about
      # to invalidate the cache anyway, so consuming it would be wasted IO.
    end
  end

  # `submission.hold_date` lives in the v3 record, which is the editable
  # source of truth — but DistributionNotifier has to find "hold date within
  # 10 days" across every submission, and a blob-backed patch chain can't be
  # filtered in SQL. So the BP Project row carries a projection of it, the
  # same way it carries status / title. Call this wherever the record
  # changes (importer, curator edit) or the notifier silently stops seeing
  # records.
  #
  # BS has nowhere to project it (no Project row) and D-way never used a BS
  # hold_date, so this is a no-op there — see DistributionNotifier.
  def sync_hold_date!(record = materialised_record)
    return unless bioproject_db? && project

    project.update_column(:hold_date, record&.dig('submission', 'hold_date'))
  end

  # Upload the freshly-computed snapshot bytes and stamp the cache
  # marker. The blob is uploaded synchronously OUTSIDE the row lock —
  # `attach(blob)` for a pre-uploaded Blob skips ActiveStorage's
  # after_commit upload deferral (CreateOne#upload has an empty
  # `when Blob` branch), so a subsequent `download` in the SAME
  # transaction sees the file. The row lock then covers only the
  # stamp/attachment swap so a slower concurrent writer cannot tear
  # the (blob, stamp) pair; if a fresher cache already won, the
  # already-uploaded blob is purged.
  #
  # `save!(validate: false)` skips the `validates :ddbj_record, ...,
  # on: :update` rule — migration-sourced submissions don't carry a
  # ddbj_record blob, and the cache write shouldn't be gated on the
  # API ingest contract.
  #
  # ORPHAN CAVEAT: same as SubmissionUpdate.create_with_patch! — an
  # outer-transaction rollback after the synchronous SeaweedFS PUT
  # leaves the file on storage with no DB row. Periodic unattached-blob
  # sweep is the right long-term cleanup; not yet wired up.
  def prime_cache!(bytes:, update_id:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           StringIO.new(bytes),
      filename:     "materialised-#{update_id}.json",
      content_type: 'application/json'
    )

    with_lock do
      if cached_at_update_id && cached_at_update_id > update_id
        blob.purge_later
        next
      end

      self.cached_materialised_record = blob
      self.cached_at_update_id        = update_id
      save!(validate: false)
    end
  rescue StandardError
    blob&.purge_later
    raise
  end

  private

  # A chain written before `ddbj-canon/v2` stored its root snapshot in raw
  # converter order, while `diff` emits indices into the canonical order —
  # so a positional patch appended to one would name the wrong element of a
  # keyed array. Rather than refuse (or corrupt), the next write to such a
  # chain replaces the whole record: one big patch, once, after which the
  # stored state is canonical and ordinary diffs are safe again.
  #
  # A chain that has never been written to is trivially canonical, so the
  # empty base is exempt.
  def heal_chain?(base)
    !base.empty? && legacy_chain?
  end

  # The state to diff against: always a real replay, never the cache.
  #
  # Reading the cache here would be faster — and was tried, to shorten the
  # window AccessionIssue holds the Sequence row locked for. It is wrong.
  # The cache can be current-looking while the chain behind it cannot
  # replay at all: the importers prime it after `safe_prior_materialised`
  # has swallowed a MaterialisationFailed, so `cached_at_update_id` names
  # the newest update while an older patch in the same chain is still
  # poisoned. Diffing against the cache would build the next patch on a
  # base the chain never produces, quietly widening the divergence instead
  # of surfacing it — and "replaying the chain reproduces the record" is
  # the property the chain exists for.
  def base_state(latest_id)
    materialise_at(update_id: latest_id)
  end

  # Root snapshots define the stored state every later diff indexes into,
  # so they are stored canonical. Inputs that canonicalisation itself
  # rejects have no canonical form — the raw tree is then all we can keep,
  # and is what the caller already expected to store.
  def snapshot_value(record)
    DDBJRecord::Canonicalizer.canonical_tree(record)
  rescue DDBJRecord::Canonicalizer::Error
    record
  end

  def write_through_cache(record, update_id)
    prime_cache!(bytes: Oj.dump(record, mode: :strict), update_id: update_id)
  rescue StandardError => e
    # Cache write failure must not break the read path — `record` is
    # already in hand. Sentry breadcrumb so persistent failures
    # (SeaweedFS down, FK violations, etc.) get noticed.
    Rails.error.report e, context: {submission_id: id, update_id: update_id}
  end
end
