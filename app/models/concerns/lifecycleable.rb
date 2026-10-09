module Lifecycleable
  extend ActiveSupport::Concern

  # Canonical name → integer mapping. Lifted to a module constant so
  # callers that work generically across Project + Sample (e.g. the
  # admin index's cross-submission bulk action) don't have to pick
  # one model's `.statuses` arbitrarily.
  STATUSES = {
    'submission_accepted'    => 5100,
    'curating'               => 5200,
    'accession_issued'       => 5300,
    'private'                => 5400,
    'public'                 => 5500,
    'withdrawn'              => 5600,
    'canceled'               => 5700,
    'permanently_suppressed' => 5800,
    'temporarily_suppressed' => 5900
  }.freeze

  # The two that mean the record is no longer part of the submission, as
  # opposed to merely not out yet. Named once because two things ask: the
  # curator lists leave them out, and so does the flatfile — for different
  # reasons, which is exactly how the two lists drift apart if each keeps
  # its own copy.
  RETRACTED = %w[canceled withdrawn].freeze

  included do
    enum :status, STATUSES, prefix: :status, validate: true

    # TODO(spike-0.8): DRAFT scopes — visibility for Temporarily / Permanently
    # Suppressed records is unresolved (waiting on curator + Confluence 1899364353).
    # Pin current behavior via test/models/concerns/lifecycleable_test.rb so the
    # final answer surfaces as a visible diff. Do NOT wire into external-facing
    # endpoints until 0.8 resolves.
    scope :publicly_visible, -> { status_public }
    scope :curator_visible,  -> { where.not(status: RETRACTED) }
    scope :retracted,        -> { where(status: RETRACTED) }

    def retracted? = status.in?(RETRACTED)
  end

  class_methods do
    # What a curator may put this kind of row into from a screen. Every
    # status, unless the model says otherwise (Entry).
    def settable_statuses = STATUSES.keys

    # What these rows may be put into: the kind's, unless some of them are
    # not curated here at all (DRASubmission).
    def settable_statuses_for(_rows) = settable_statuses

    # Whether this kind of row keeps when it was published (DB-2096): when
    # it was first made public, and when what is public about it last
    # changed — on the way into public, while public, and on the way out.
    def publication_tracked? = column_names.include?('last_published_at')

    # What a row is the submitter's name for, to set beside its accession
    # in a notice. None by default.
    def notice_name_column = nil

    # Every change of status goes through here, so that crossing into or
    # out of public carries the publication timestamps with it: into
    # public, `first_published_at` if there is none yet and
    # `last_published_at`; out of it, `last_published_at`. One statement,
    # each row judged by the status it had — a row already where it is
    # going moves nothing but `updated_at`.
    #
    # A row made public for the first time is announced to its submitter
    # too (SubmissionNotice.published!), one notice a submission: that is
    # the other thing crossing into public carries with it, and the reason
    # it is here rather than on each screen is the same. In one
    # transaction with the write, because several screens call this with
    # none open, and a status committed without its notice would never be
    # announced — the row is first-published from then on.
    #
    # Not by callback: the screens that change status change many rows at
    # once, and `update_all` runs none.
    def move_to_status!(status, at: Time.current)
      code        = STATUSES.fetch(status.to_s)
      public_code = STATUSES.fetch('public')
      attrs       = {status: code, updated_at: at}

      transaction do
        # Read before the write, which makes them indistinguishable from
        # the rows that were public already.
        debuts = (code == public_code && publication_tracked?) ? first_publications : {}

        if publication_tracked?
          column   = ->(name) { "#{quoted_table_name}.#{connection.quote_column_name(name)}" }
          crossing = "#{column.('status')} #{code == public_code ? '<>' : '='} #{public_code}"

          attrs[:last_published_at]  = Arel.sql(sanitize_sql(["CASE WHEN #{crossing} THEN ? ELSE #{column.('last_published_at')} END", at]))
          attrs[:first_published_at] = Arel.sql(sanitize_sql(["COALESCE(#{column.('first_published_at')}, ?)", at])) if code == public_code
        end

        count = update_all(attrs)

        announce debuts

        count
      end
    end

    # What is public about these rows has changed: the public ones among
    # them are published again, as they stand now.
    def republished!(at: Time.current) = status_public.update_all(last_published_at: at)

    private

    # The rows about to be public for the first time, as {submission_id =>
    # [accession, ...]}. Locked, so that a second publish of the same rows
    # at the same moment waits for this one and then finds them published.
    def first_publications
      rows = where(first_published_at: nil).where.not(status: :public).where.not(accession: nil)

      rows.lock.order(:accession).pluck(:submission_id, :accession).group_by(&:first).transform_values { it.map(&:last) }
    end

    # Names for only what a notice lists: a submission can make a hundred
    # thousand samples public at once.
    def announce(debuts)
      Submission.where(id: debuts.keys).includes(:request).find_each do |submission|
        # Nowhere to be told. Every submission is applied from a request,
        # but nothing here depends on that.
        next unless submission.request

        accessions = debuts.fetch(submission.id)
        listed     = accessions.first(SubmissionNotice::LIST_LIMIT)
        names      = notice_name_column ? unscoped.where(accession: listed).pluck(:accession, notice_name_column).to_h : {}

        SubmissionNotice.published!(submission, accessions, names:)
      end
    end
  end
end
