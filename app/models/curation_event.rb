# One curator action that could not be reduced to a patch.
#
# The two histories divide on reducibility, not on membership: an action
# the patch chain can express becomes a SubmissionUpdate, and the chain
# stays a pure record history. What is left over lands here.
#
# Two different reasons an action lands here:
#   - It is not record content at all — status and assignee are typed
#     columns on Project / Sample, and curator_comment is a Submission
#     column the v3 record never carries.
#   - It IS record content, but not diffable. `/**/accession` is a
#     registered volatile path (schema/canon/array-modes.yml, "archive-
#     assigned, not curator data"), so `Canonicalizer.diff` strips it from
#     both sides and issuance produces an empty patch. The typed column is
#     authoritative; see AccessionIssue.
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
    parts << "set #{subject} to #{details['status']}"        if details['status']
    parts << "assigned #{parts.any? ? 'them' : subject} to #{details['assignee']}" if details['assignee']
    parts << 'updated the curator comment'                   if details['curator_comment']

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
