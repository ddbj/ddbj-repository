# "Who did what to this request", in words a curator can read.
#
# The underlying history is spread across four tables and phrased in the
# vocabulary of the machinery — a SubmissionUpdate is a row with a source
# enum and a JSON Patch blob, not a sentence. This merges them into one
# reverse-chronological list where each line names an actor and an action,
# and keeps the technical handle (`patch #318`) as a trailing reference
# rather than as the content. The raw ops stay one tab away, on
# Record & history.
class ActivityFeed
  # `update_id` is set when the line came from a SubmissionUpdate, so the
  # view can deep-link to that snapshot; nil for messages and imports.
  Entry = Data.define(:at, :actor, :summary, :update_id)

  SOURCE_VERBS = {
    'manual'     => 'edited the record',
    'migration'  => 'imported the record from D-way',
    'batch'      => 'updated the record in a batch run',
    'tsv_import' => 'applied a sample TSV import'
  }.freeze

  def initialize(request)
    @request    = request
    @submission = request.submission
  end

  # Newest first. Bounded by `limit` because a migrated BS submission can
  # carry a long chain and the Overview only wants the recent past — the
  # full chain lives on Record & history.
  def entries(limit: 12)
    (request_entries + message_entries + update_entries + tsv_entries + event_entries).max_by(limit, &:at)
  end

  private

  attr_reader :request, :submission

  def request_entries
    verb = request.migration_origin? ? 'was created by a migration run' : 'submitted this request'

    [Entry.new(at: request.created_at, actor: request.user.uid, summary: verb, update_id: nil)]
  end

  def message_entries
    request.messages.map {|message|
      Entry.new(
        at:        message.created_at,
        actor:     message.user.uid,
        summary:   message.curator_role? ? 'posted a message to the submitter' : 'replied to the curator',
        update_id: nil
      )
    }
  end

  # The chain rows carry an actor string ("admin:tanaka", "migration:…")
  # rather than a user id, so they are shown as-is. Op counts are
  # deliberately not computed: each would mean downloading a patch blob,
  # and a 100K-sample TSV import writes multi-megabyte patches.
  #
  # A chain entry an event already describes is skipped: accession issuance
  # both patches the record and records what it did, and "edited the
  # record" adds nothing beside "issued 1,842 SAMD accessions".
  def update_entries
    return [] unless submission

    submission.updates.where.not(id: described_update_ids).order(id: :desc).limit(20).map {|update|
      Entry.new(
        at:        update.created_at,
        actor:     actor_label(update.actor),
        summary:   SOURCE_VERBS.fetch(update.source, 'updated the record'),
        update_id: update.id
      )
    }
  end

  def described_update_ids
    @described_update_ids ||= submission.curation_events.where.not(submission_update_id: nil).pluck(:submission_update_id)
  end

  # Curator actions in words. Most carry no snapshot to link to — status,
  # assignee and the comment are not record content — so their reference
  # column stays empty. Accession issuance is the exception: it patches the
  # record too, and links to that entry (which update_entries then omits).
  def event_entries
    return [] unless submission

    submission.curation_events.limit(20).map {|event|
      Entry.new(
        at:        event.created_at,
        actor:     event.actor_label,
        summary:   event.summary,
        update_id: event.submission_update_id
      )
    }
  end

  def tsv_entries
    return [] unless submission

    submission.sample_tsv_imports.map {|import|
      Entry.new(
        at:      import.finished_at || import.started_at,
        actor:   actor_label(import.actor),
        summary: tsv_summary(import),
        update_id: nil
      )
    }
  end

  def tsv_summary(import)
    counts = "#{ActiveSupport::NumberHelper.number_to_delimited(import.processed)} " \
             "#{'row'.pluralize(import.processed)}, " \
             "#{ActiveSupport::NumberHelper.number_to_delimited(import.failed)} " \
             "#{'error'.pluralize(import.failed)}"

    case import.status
    when 'completed' then "uploaded a sample TSV — #{counts}"
    when 'failed'    then "uploaded a sample TSV that failed — #{counts}"
    else                  "is uploading a sample TSV — #{counts} so far"
    end
  end

  # Chain actors are namespaced strings ("admin:tanaka", "migration:foo").
  # The namespace is noise in a sentence that already says what happened.
  def actor_label(actor)
    actor.to_s.split(':', 2).last.presence || 'system'
  end
end
