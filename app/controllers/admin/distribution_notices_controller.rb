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

    def index
      @tab = TABS.include?(params[:tab]) ? params[:tab] : 'due'

      # The tab badge is on screen whichever tab is open, so the count is
      # its own query rather than a by-product of loading the due list.
      @due_count = DistributionNotifier.new.candidates.select(:submission_id).count

      case @tab
      when 'due'      then load_due
      when 'sent'     then load_sent
      when 'template' then load_template
      end
    end

    # "Send now" — all pending, or just one submitter's when user_id is
    # given. Recorded as a manual send so the history can say who.
    def create
      projects = DistributionNotifier.new.candidates.to_a
      projects = projects.select { it.submission.user_id == params[:user_id].to_i } if params[:user_id].present?

      result = DistributionNotifier.new.notify(projects, trigger: :manual, actor: "admin:#{current_user.uid}")

      notice = "Sent #{result.notified_project_count} notice(s) to #{result.notified_user_count} submitter(s)."
      notice += " #{result.skipped_user_count} submitter(s) skipped: no address on file." if result.skipped_user_count.positive?

      redirect_to admin_distribution_notices_path, notice:
    end

    # Mail the current template to the curator editing it, rendered from a
    # real candidate. Saving a template is publishing it — every submitter
    # gets the next one — so being able to look at the actual mail first
    # is the difference between editing and gambling.
    #
    # Deliberately not `DistributionNotifier#notify`: nothing is marked
    # notified, nobody else is written to, and it leaves no send-log row.
    # A test is not a notice.
    def test_delivery
      unless current_user.email.present?
        return redirect_to admin_distribution_notices_path(tab: 'template'),
                           alert: 'Your own account has no address on file, so there is nowhere to send a test.'
      end

      projects = preview_projects

      if projects.empty?
        return redirect_to admin_distribution_notices_path(tab: 'template'),
                           alert: 'Nothing is due, so there is no real notice to render.'
      end

      DistributionNotifierMailer.with(user: current_user, projects:).release_notice.deliver_later

      redirect_to admin_distribution_notices_path(tab: 'template'),
                  notice: "Test notice sent to #{current_user.email}."
    end

    private

    def load_due
      candidates = DistributionNotifier.new.candidates.to_a

      @by_user  = candidates.group_by { it.submission.user }
      @projects = candidates
      @blocked  = @by_user.keys.reject { it.email.present? }
      @blocked_since = DistributionNotice.blocked_since(@blocked.map(&:id))
    end

    def load_sent
      scope = DistributionNotice.since(SENT_WINDOW.ago).includes(:user)
      scope = filter_sent(scope, params[:q])

      @pagy, @notices = pagy(scope.recent, limit: 50)
      @sent_total     = DistributionNotice.since(SENT_WINDOW.ago).count
    end

    # One box over the two things somebody arrives holding: a submitter or
    # an accession. Accessions live in a jsonb array, so the containment
    # operator does the work the LIKE would otherwise fake.
    def filter_sent(scope, raw)
      value = raw.to_s.strip
      return scope if value.blank?

      scope.where(<<~SQL.squish, uid: "#{ActiveRecord::Base.sanitize_sql_like(value)}%", accession: [value].to_json)
        EXISTS (SELECT 1 FROM users WHERE users.id = distribution_notices.user_id AND users.uid ILIKE :uid) OR
        distribution_notices.accessions @> :accession::jsonb
      SQL
    end

    def load_template
      @template = DistributionNotifierTemplate.instance
      @preview  = DistributionNoticePreview.new(@template, preview_projects)
    end

    # A real candidate, so the preview shows what will actually be sent
    # rather than a specimen nobody recognises. First by nearest release,
    # matching the order the due list is read in.
    def preview_projects
      DistributionNotifier.new.candidates.to_a.group_by { it.submission.user }.values.first.to_a
    end
  end
end
