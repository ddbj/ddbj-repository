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

  # Curators who have worked on this — see SubmissionRequestParticipant
  # for why this is separate from `assignee`.
  has_many :participations, class_name: 'SubmissionRequestParticipant', dependent: :destroy
  has_many :participants, through: :participations, source: :user

  # Who is actually following it. `participants` is everyone who has ever
  # worked here, which is a fact about the past; this is the one to show
  # and to notify, or a curator who stopped following goes on being
  # listed as though they had not.
  has_many :followers, -> { merge(SubmissionRequestParticipant.subscribed) },
           through: :participations, source: :user

  has_one :reviewer_access, dependent: :destroy

  has_one_attached :ddbj_record

  scope :assigned_to, ->(user) { where(assignee_id: user.id) }
  scope :unassigned,  -> { where(assignee_id: nil) }

  scope :involving, ->(user) {
    where(id: SubmissionRequestParticipant.subscribed.where(user_id: user.id).select(:submission_request_id))
  }

  # Nobody owns it and nobody has answered. Shown to every curator
  # identically, because a request in this state is not anyone's to
  # notice — if the section is never empty, that is a staffing signal
  # rather than an individual's backlog.
  #
  # Subscribed participations only: if everyone who touched it has since
  # stopped following, nobody is watching it, and that is exactly what
  # this section is for. Keying on the row's mere existence would leave
  # such a request owned by nobody and visible to nobody.
  scope :unclaimed, -> {
    unassigned.where.not(id: SubmissionRequestParticipant.subscribed.select(:submission_request_id))
  }

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

  # The predicate itself, as a constant rather than built inside each
  # reader: the ORDER BY wraps it in `(...) DESC`, and interpolating a
  # method's return value into SQL is indistinguishable — to Brakeman and
  # to a reader — from interpolating a parameter. A constant is neither.
  NEEDS_SUBMITTER_ACTION = <<~SQL.squish
    submission_requests.closed_at IS NULL AND (
    submission_requests.status IN (:statuses) OR
    EXISTS (
      SELECT 1 FROM submission_messages
      WHERE submission_messages.submission_request_id = submission_requests.id
        AND submission_messages.author_role = :role
        AND submission_messages.read_at IS NULL
    ))
  SQL

  def self.needs_submitter_action_binds
    {statuses: ACTION_STATUSES.map { statuses.fetch(it) }, role: 'curator'}
  end

  def self.needs_submitter_action_sql
    sanitize_sql_array([NEEDS_SUBMITTER_ACTION, needs_submitter_action_binds])
  end

  # "Needs you" floats to the top of the whole list, not just of whichever
  # page you are on, so the sort has to happen in SQL.
  def self.needs_submitter_action_order
    Arel.sql(sanitize_sql_array(["(#{NEEDS_SUBMITTER_ACTION}) DESC", needs_submitter_action_binds]))
  end

  # "Nothing further will happen here": every curation row has reached a
  # terminal status — released, or off the pipeline altogether — or, for a
  # database this system does not curate (ST.26), the file has been
  # applied. A request with no submission yet is never finished, unless
  # the submitter has said so themselves — which is the only way an
  # attempt that failed validation ever reaches an end, since nothing
  # advances it and a corrected file arrives as a new request.
  FINISHED_ROW_STATUSES = (['public'] + CurationState::CLOSED_STATUSES).freeze

  def self.finished_sql
    sids = FINISHED_ROW_STATUSES.map { Lifecycleable::STATUSES.fetch(it) }

    sanitize_sql_array([<<~SQL.squish, sids:, applied: statuses.fetch('applied')])
      submission_requests.closed_at IS NOT NULL OR (
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

  def closed? = closed_at?

  # Only what is asking for something can be put down. A request being
  # validated or applied is in flight, and one that has been applied has
  # a submission whose end is the curator's to declare (withdrawn,
  # canceled) — a second notion of "closed" on the request would put the
  # same fact in two places.
  def closable? = !closed? && ACTION_STATUSES.include?(status)

  # Straight to the column, for the same reason `assign!` is: `validates
  # :ddbj_record, attached: true` guards the submitter's upload flow, and
  # letting it refuse a closure would mean a request whose blob went
  # missing could never be put down — which is exactly the request most
  # likely to need it.
  def close!  = update_columns(closed_at: Time.current, updated_at: Time.current)

  def reopen! = update_columns(closed_at: nil, updated_at: Time.current)

  # A closure says "I am not taking this further". Anything that makes
  # that untrue lifts it, rather than leaving a request that is closed
  # and asking for something at the same time — which would be invisible
  # twice over, since a closed request counts as finished and so is not
  # even in the list a submitter opens by default.
  # Not an endless method: a trailing `if` there binds to the definition
  # itself, so the method is defined only when the class body happens to
  # be truthy — which is never, and silently.
  def reopen_if_closed!
    reopen! if closed?
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

    # Deliberately no subscription and no marker. Claiming says who owns
    # this; it is not a claim to have read anything, and it must not
    # discharge the very question that prompted the claim. The assignee
    # reaches their queue through `assigned_to` regardless, and an absent
    # marker already means "nothing put aside".
  end

  # What is waiting on THIS curator: unanswered, and not already put
  # aside by them.
  #
  # No marker means "nothing put aside", not "nothing read" — the
  # baseline is the thread's own state, so taking on a request whose
  # conversation was settled long ago does not report its whole history
  # as unread. A colleague ANSWERING settles it for everyone, because
  # that is the work; a colleague reading settles nothing, which is the
  # whole point of the marker.
  def unread_message_count_for(user)
    return 0 unless user

    marker = participations.find_by(user_id: user.id)&.last_read_at
    scope  = messages.unanswered
    scope  = scope.where('submission_messages.created_at > ?', marker) if marker

    scope.count
  end

  # "I have seen this thread, up to here."
  #
  # `through` is the newest message the curator had in front of them. A
  # question that lands while a reply is being typed has not been read by
  # sending that reply, and stamping `now` would discharge it unseen —
  # the same lost reminder this whole model exists to stop, in a narrower
  # window. Absent, it means the thread as it stands.
  def mark_read_by!(user, through: nil)
    return unless user&.admin?

    at = through ? messages.where(id: through).pick(:created_at) : Time.current
    return unless at

    # Creates the row it needs to write on, but NOT as a subscription:
    # acknowledging a thread is the opposite of asking to hear more about
    # it, and enrolling a curator who glanced at an unclaimed request
    # would put it in their queue from then on. An existing row keeps
    # whatever it already said — ON CONFLICT DO NOTHING — so this never
    # unsubscribes anybody either.
    SubmissionRequestParticipant.insert_all(
      [{submission_request_id: id, user_id: user.id, created_at: Time.current, unsubscribed_at: Time.current}],
      unique_by: %i[submission_request_id user_id]
    )

    # Never backwards. A stale tab, rendered when more was unread, would
    # otherwise reset the position to an older message and resurrect
    # everything already dealt with.
    participations.where(user_id: user.id)
                  .where('last_read_at IS NULL OR last_read_at < ?', at)
                  .update_all(last_read_at: at)
  end

  # Who hears about a message on this request, apart from whoever wrote
  # it and anyone being copied in on it — they get a more direct mail.
  # Asked by both the mailer and the caller that decides whether there is
  # anything to enqueue, so the two cannot drift.
  def followers_to_notify(message)
    told = [message.user_id, *message.cc_user_ids]

    followers.reject { told.include?(it.id) }
  end

  def following?(user)
    return false unless user

    participations.subscribed.exists?(user_id: user.id)
  end

  # Acting on a request follows it, which is why replying re-subscribes:
  # a curator who steps back in has stepped back in. Marking a thread
  # read is not that — it is the opposite — so it does not come through
  # here.
  def subscribe!(user)
    participate!(user)
    participations.where(user_id: user.id).update_all(unsubscribed_at: nil)
  end

  # Stops it surfacing in this curator's queue. The participation stays:
  # they did work here, and that is a fact about the past rather than a
  # preference about the future.
  def unsubscribe!(user)
    participate!(user)
    participations.where(user_id: user.id).update_all(unsubscribed_at: Time.current)
  end

  # Called as a side effect of a curator doing something here, so it must
  # never fail the action it hangs off: already-a-participant is a no-op
  # (ON CONFLICT DO NOTHING), and a submitter acting on their own request
  # is simply not a participant.
  def participate!(user)
    return unless user&.admin?

    SubmissionRequestParticipant.insert_all(
      [{submission_request_id: id, user_id: user.id, created_at: Time.current}],
      unique_by: %i[submission_request_id user_id]
    )
  end

  private

  def assignee_must_be_admin
    return if assignee.nil? || assignee.admin?

    errors.add(:assignee, 'must be an admin user')
  end
end
