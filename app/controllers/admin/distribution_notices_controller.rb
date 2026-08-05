module Admin
  # Release notices (DB-2005). The real mechanism is the daily job; this
  # screen is for the exceptions and for answering questions about it
  # afterwards.
  #
  # It used to show only the queue of who is next, which meant the one
  # question people actually arrive with — "was this submitter told?" —
  # had no answer anywhere. Hence three tabs on one screen: what is about
  # to go out, what has gone out, and what it says.
  class DistributionNoticesController < ApplicationController
    TABS = %w[due sent template].freeze

    SENT_WINDOW = 90.days

    # Submitters, not projects: one mail goes to each, so that is the size
    # of the work. On screen whichever tab is open, hence its own query
    # rather than a by-product of loading the due list — and a class
    # method because the template controller re-renders this screen too.
    def self.due_count
      DistributionNotifier.new.candidates.joins(:submission).distinct.count('submissions.user_id')
    end

    def index
      @tab       = TABS.include?(params[:tab]) ? params[:tab] : 'due'
      @due_count = self.class.due_count

      case @tab
      when 'due'      then load_due
      when 'sent'     then load_sent
      when 'template' then load_template
      end
    end

    # The confirmation, for both Send buttons. Mail cannot be recalled,
    # and the queue-wide one used to ask with a line of window.confirm
    # while the per-submitter one asked nothing at all — the same
    # outward-facing action with less friction on the version that is
    # pressed more often.
    def new
      @plan   = DistributionPlan.for(DistributionNotifier.new.candidates.to_a, user: confirmed_user)
      @action = admin_distribution_notices_path
      @cancel = admin_distribution_notices_path
    end

    # "Send now" — all pending, or just one submitter's when user_id is
    # given. Recorded as a manual send so the history can say who.
    def create
      projects = DistributionNotifier.new.candidates.to_a
      projects = projects.select { it.submission.user_id == params[:user_id].to_i } if params[:user_id].present?

      result = DistributionNotifier.new.notify(projects, trigger: :manual, actor: current_actor)

      notice = "Sent #{helpers.pluralize(result.notified_project_count, 'notice')} " \
               "to #{helpers.pluralize(result.notified_user_count, 'submitter')}."

      if result.skipped_user_count.positive?
        notice += " #{helpers.pluralize(result.skipped_user_count, 'submitter')} skipped: no address on file."
      end

      redirect_to admin_distribution_notices_path, notice:
    end

    private

    def confirmed_user = params[:user_id].presence && User.find(params[:user_id])

    def load_due
      candidates = DistributionNotifier.new.candidates.to_a

      @by_user  = candidates.group_by { it.submission.user }
      @projects = candidates
      @blocked  = @by_user.keys.reject { it.email.present? }
      @blocked_since = DistributionNotice.blocked_since(@blocked.map(&:id))
    end

    def load_sent
      window = DistributionNotice.since(SENT_WINDOW.ago)

      @pagy, @notices = pagy(filter_sent(window.includes(:user), params[:q]).recent, limit: 50)
      @sent_total     = window.count
    end

    # One box over the two things somebody arrives holding: a submitter or
    # an accession. Both halves behave the same way — case-insensitive
    # prefix — because a box that takes either must not silently fail on
    # the one typed in the wrong case.
    def filter_sent(scope, raw)
      value = raw.to_s.strip
      return scope if value.blank?

      scope.where(<<~SQL.squish, pattern: "#{ActiveRecord::Base.sanitize_sql_like(value)}%")
        EXISTS (SELECT 1 FROM users WHERE users.id = distribution_notices.user_id AND users.uid ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM jsonb_array_elements_text(distribution_notices.accessions) accession WHERE accession ILIKE :pattern)
      SQL
    end

    def load_template
      @template = DistributionNotifierTemplate.instance
      @preview  = DistributionNoticePreview.for(@template)
    end
  end
end
