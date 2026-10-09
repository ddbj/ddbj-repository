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

    # Every change of status goes through here, so that crossing into or
    # out of public carries the publication timestamps with it: into
    # public, `first_published_at` if there is none yet and
    # `last_published_at`; out of it, `last_published_at`. One statement,
    # each row judged by the status it had — a row already where it is
    # going moves nothing but `updated_at`.
    #
    # Not by callback: the screens that change status change many rows at
    # once, and `update_all` runs none.
    def move_to_status!(status, at: Time.current)
      code  = STATUSES.fetch(status.to_s)
      attrs = {status: code, updated_at: at}

      if publication_tracked?
        public   = STATUSES.fetch('public')
        column   = ->(name) { "#{quoted_table_name}.#{connection.quote_column_name(name)}" }
        crossing = "#{column.('status')} #{code == public ? '<>' : '='} #{public}"

        attrs[:last_published_at]  = Arel.sql(sanitize_sql(["CASE WHEN #{crossing} THEN ? ELSE #{column.('last_published_at')} END", at]))
        attrs[:first_published_at] = Arel.sql(sanitize_sql(["COALESCE(#{column.('first_published_at')}, ?)", at])) if code == public
      end

      update_all(attrs)
    end

    # What is public about these rows has changed: the public ones among
    # them are published again, as they stand now.
    def republished!(at: Time.current) = status_public.update_all(last_published_at: at)
  end
end
