class SubmissionRequest < ApplicationRecord
  include ValidationSubject

  enum :db, {
    st26:       'st26',
    bioproject: 'bioproject',
    biosample:  'biosample'
  }, suffix: true, validate: true

  belongs_to :user
  belongs_to :submission, optional: true, inverse_of: :request

  # Who has taken this on. One curator per request, never per curation
  # row: D-way holds the same fact on the submission (`charge_id`) and
  # only splits *status* per sample, and a request that has not been
  # applied yet has no rows to hang an assignee off at all.
  belongs_to :assignee, class_name: 'User', optional: true

  validate :assignee_must_be_admin

  has_many :messages, -> { chronological }, class_name: 'SubmissionMessage', dependent: :destroy

  has_one :reviewer_access, dependent: :destroy

  has_one_attached :ddbj_record

  scope :assigned_to, ->(user) { where(assignee_id: user.id) }
  scope :unassigned,  -> { where(assignee_id: nil) }

  # What is on the submitter rather than on us: a file that failed
  # validation, a validated file waiting for them to press Apply, or a
  # curator question nobody has answered. A failed *application* is
  # deliberately absent — that one is ours to fix, and telling the
  # submitter to act on it only makes them resubmit a file that was fine.
  #
  # Exposed as SQL as well as a scope because the list also ORDERs by it:
  # "needs you" has to float to the top of the whole list, not just of
  # whichever page you happen to be on.
  ACTION_STATUSES = %w[validation_failed ready_to_apply].freeze

  def self.needs_submitter_action_sql
    sanitize_sql_array([<<~SQL.squish, statuses: ACTION_STATUSES.map { statuses.fetch(it) }, role: 'curator'])
      submission_requests.status IN (:statuses) OR
      EXISTS (
        SELECT 1 FROM submission_messages
        WHERE submission_messages.submission_request_id = submission_requests.id
          AND submission_messages.author_role = :role
          AND submission_messages.read_at IS NULL
      )
    SQL
  end

  # "Nothing further will happen here": every curation row has reached a
  # terminal status — released, or off the pipeline altogether — or, for a
  # database this system does not curate (ST.26), the file has been
  # applied. A request with no submission yet is never finished.
  FINISHED_ROW_STATUSES = (['public'] + CurationState::CLOSED_STATUSES).freeze

  def self.finished_sql
    sids = FINISHED_ROW_STATUSES.map { Lifecycleable::STATUSES.fetch(it) }

    sanitize_sql_array([<<~SQL.squish, sids:, applied: statuses.fetch('applied')])
      (
        (
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id)
        ) AND
        NOT EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.status NOT IN (:sids)) AND
        NOT EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.status  NOT IN (:sids))
      ) OR (
        submission_requests.db = 'st26' AND submission_requests.status = :applied
      )
    SQL
  end

  scope :needs_submitter_action, -> { where(needs_submitter_action_sql) }
  scope :finished,               -> { where(finished_sql) }
  scope :unfinished,             -> { where.not(finished_sql) }

  # Interactive requests always carry the uploaded JSON. Synthetic
  # requests minted by the BP/BS importer (marked by migration_run_id)
  # wrap an already-materialised submission and have no upload, so the
  # attachment rule is waived for them.
  validates :ddbj_record, attached: true, content_type: 'application/json', unless: :migration_origin?

  def migration_origin?
    migration_run_id.present?
  end

  # Claiming a request is a curator-internal write, so it goes straight to
  # the column rather than through `save`: `validates :ddbj_record,
  # attached: true` guards the submitter's upload flow, and letting it
  # refuse an assignment would make migration-sourced requests — which
  # carry no upload at all — permanently unclaimable. The one rule that
  # does apply is enforced here.
  def assign!(user)
    raise ArgumentError, 'Assignee must be an admin user.' unless user.nil? || user.admin?

    update_columns(assignee_id: user&.id, updated_at: Time.current)
  end

  private

  def assignee_must_be_admin
    return if assignee.nil? || assignee.admin?

    errors.add(:assignee, 'must be an admin user')
  end
end
