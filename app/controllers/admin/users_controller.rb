module Admin
  # Looking a person up, not browsing a directory.
  #
  # This was a list with a 100-row cap and a "please narrow your search"
  # caveat above it — which is to say a search screen that had not admitted
  # it. So search leads, the cap is stated on the result line where it is
  # relevant, and the segments answer the question the `include_inactive`
  # checkbox was standing in for.
  #
  # Two rules the old screen broke, both of which made real accounts
  # unfindable: a row whose DDBJ Account profile could not be fetched was
  # silently dropped, and a query was matched against the profiles of the
  # first 100 uids only, so anyone past that point could never be found at
  # all. Neither failure was visible from the screen.
  class UsersController < ApplicationController
    include RequestListing

    LIMIT = 100

    # Which population is being looked at. `admin` is not a column a
    # curator should have to read off a row — it is the question "who is
    # staff", so it becomes a segment.
    SEGMENTS = {
      'submitters' => 'Submitters',
      'staff'      => 'Staff',
      'everyone'   => 'Everyone'
    }.freeze

    before_action :load_user_detail, only: %i[show update]

    def index
      @segment = SEGMENTS.key?(params[:segment]) ? params[:segment] : 'submitters'
      @query   = params[:q].to_s.strip

      # "Curators who have submitted something" is a coherent query and
      # almost never the one being asked — and with the filter defaulting
      # to on, clicking Staff showed an empty list directly beneath a
      # badge counting every one of them. Off there, and the control is
      # hidden rather than left ticked over a list ignoring it.
      @submitted   = @segment != 'staff' && (params.key?(:submitted) ? params[:submitted].present? : true)
      @staff_count = User.staff.count

      scope   = filtered(User.all)
      @total  = scope.count
      @users  = scope.order(:uid).limit(LIMIT).to_a
      @counts = activity_counts(@users.map(&:id))

      # Absent profiles are rendered as such rather than removed, so a
      # DDBJ Account outage narrows what a row *says*, never which rows
      # exist.
      @profiles_by_uid = fetch_profiles(@users.map(&:uid))
    end

    def show
      @recent = @user.submission_requests.includes(:submission).order(updated_at: :desc).limit(RECENT_REQUESTS).to_a

      # The same aggregate the ledger's rows use, so "where it is now"
      # reads identically in both places.
      @sample_aggregates = sample_aggregates_for(@recent.filter_map(&:submission))
    end

    def update
      @user.update_notes!(params.expect(user: [:notes])[:notes], by: current_user)

      redirect_to admin_user_path(uid: @user.uid), notice: 'Notes saved.', status: :see_other
    end

    # Enough to see where this person is at without a detour through the
    # ledger, few enough that the card stays a summary.
    RECENT_REQUESTS = 3

    private

    def filtered(scope)
      scope = by_segment(scope)

      scope = scope.with_submission_requests if @submitted
      scope = search(scope)                  if @query.present?

      scope
    end

    def by_segment(scope)
      case @segment
      when 'staff'    then scope.staff
      when 'everyone' then scope
      else                 scope.submitters
      end
    end

    # The uid is matched locally so the search always works, even when
    # DDBJ Account is unreachable; name / organization / email live over
    # there, so those matches come back as a set of uids and widen it. The
    # old code did the reverse — filter a remote search down to the first
    # 100 local uids — which silently hid anyone further down the alphabet.
    def search(scope)
      scope.uid_matching(@query).or(scope.where(uid: remote_uids))
    end

    def remote_uids
      CloakmanClient.new.search(@query).map { it['uid'] }
    rescue Faraday::Error
      []
    end

    # A profile we cannot fetch is a fact about the fetch, not about the
    # user. Returning {} lets every row render with what we hold locally.
    def fetch_profiles(uids)
      CloakmanClient.new.lookup(uids).index_by { it['uid'] }
    rescue Faraday::Error
      {}
    end

    def load_user_detail
      @user    = User.find_by!(uid: params[:uid])
      @profile = fetch_profiles([@user.uid])[@user.uid]
      @counts  = activity_counts([@user.id])
    end

    def activity_counts(user_ids)
      rows = SubmissionRequest
        .where(user_id: user_ids)
        .group(:user_id)
        .pluck(:user_id, Arel.sql('COUNT(*)'), Arel.sql('COUNT(submission_id)'), Arel.sql('MAX(updated_at)'))

      requests    = Hash.new(0)
      submissions = Hash.new(0)
      last_seen   = {}

      rows.each do |user_id, request_count, submission_count, last_activity|
        requests[user_id]    = request_count
        submissions[user_id] = submission_count
        last_seen[user_id]   = last_activity
      end

      {requests:, submissions:, last_activity: last_seen}
    end
  end
end
