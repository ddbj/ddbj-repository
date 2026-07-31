# One curator action that could not be reduced to a patch.
#
# The two histories divide on reducibility, not on membership: an action
# the patch chain can express becomes a SubmissionUpdate, and the chain
# stays a pure record history. What is left over lands here.
#
# What lands here is what the record does not carry: status and assignee
# are typed columns on Project / Sample, and curator_comment is a
# Submission column the v3 record never mentions. Before this table they
# left nothing behind but a bumped `updated_at`, with no actor.
#
# Accession issuance is the one action that produces both. Since
# ddbj-canon/v2 it patches the record like any other edit (the mechanical
# truth), and also records an event saying what the change was in words,
# linked to that patch via `submission_update` so the activity feed shows
# one line rather than two.
#
# Append-only. Rows are written by the services that perform the action,
# never edited afterwards.
class CurationEvent < ApplicationRecord
  ACTIONS = %w[curation_updated accession_issued].freeze

  belongs_to :submission

  # Set when the action ALSO patched the record — accession issuance does,
  # since v2. The feed renders the event's sentence and links it to this
  # entry rather than printing both. Nil for actions that are not record
  # content at all.
  belongs_to :submission_update, optional: true

  enum :action, ACTIONS.index_with(&:itself), validate: true

  validates :actor, presence: true

  scope :recent, -> { order(created_at: :desc) }

  # `details` is written by the caller as a plain hash; blank values are
  # dropped so "assignee was not touched" and "assignee was cleared" stay
  # distinguishable (the latter records the key with an explicit nil-ish
  # marker chosen by the caller, e.g. 'unassigned').
  def self.record!(submission:, actor:, action:, row_count: 0, submission_update: nil, **details)
    create!(submission:, actor:, action:, row_count:, submission_update:,
            details: details.compact.stringify_keys)
  end

  # Curator-facing sentence for the activity feed. Phrasing lives with the
  # data so a stored event can be re-worded later without a migration.
  def summary
    case action
    when 'curation_updated'  then curation_summary
    when 'accession_issued'  then accession_summary
    else                          action.tr('_', ' ')
    end
  end

  # The namespace on a stored actor ("admin:tanaka") is noise in a sentence
  # that already says what happened.
  def actor_label = actor.to_s.split(':', 2).last.presence || 'system'

  private

  def curation_summary
    parts = []
    parts << "set #{subject} to #{details['status']}" if details['status']

    # Assignment is a fact about the request, not about the rows — so it
    # never borrows `subject`, which counts rows and would report
    # "assigned 0 samples" for a request that has not been applied yet.
    if (assignee = details['assignee'])
      parts << (assignee == 'unassigned' ? 'unassigned the request' : "assigned the request to #{assignee}")
    end

    parts << 'updated the curator comment' if details['curator_comment']

    parts.any? ? parts.to_sentence : "updated #{subject}"
  end

  def accession_summary
    count  = ActiveSupport::NumberHelper.number_to_delimited(row_count)
    prefix = details['prefix'].presence

    "issued #{count} #{"#{prefix} " if prefix}#{'accession'.pluralize(row_count)}"
  end

  def subject
    noun = details['noun'].presence || 'row'

    "#{ActiveSupport::NumberHelper.number_to_delimited(row_count)} #{noun.pluralize(row_count)}"
  end
end
