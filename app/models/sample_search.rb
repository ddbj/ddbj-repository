# Narrows a BS submission's samples down to "the group I am fixing right
# now". A submission can carry 100K samples, so the Samples screen is
# useless without this: the curator never wants the whole bag, they want
# the un-accessioned ones, or the ones assigned to them, or the ones whose
# name matches something.
#
# The same object backs the list and the bulk action, so "apply to all
# rows matching the filter" re-derives the target set server-side from the
# posted filter rather than trusting a client-supplied id list — which is
# the only way that button can mean what it says at 100K rows.
class SampleSearch
  FILTER_KEYS = %i[q status assignee accession].freeze

  ACCESSION_STATES = {
    'issued'     => 'Issued',
    'not_issued' => 'Not issued'
  }.freeze

  def initialize(relation, params)
    @relation = relation
    @params   = params
  end

  def scope
    [:search, :by_status, :by_assignee, :by_accession].reduce(@relation) {|scope, step| send(step, scope) }
  end

  def q = @params[:q].to_s.strip

  def statuses = @statuses ||= Array(@params[:status]).map(&:to_s) & Sample.statuses.keys

  # Assignee values are user ids, plus `0` for "unassigned" — the same
  # sentinel the request list uses.
  def assignees = @assignees ||= Array(@params[:assignee]).map(&:to_s).reject(&:blank?)

  def accession_state
    ACCESSION_STATES.key?(@params[:accession]) ? @params[:accession] : nil
  end

  def active?
    q.present? || statuses.any? || assignees.any? || accession_state
  end

  # The current filter as query params, so pagination links and the bulk
  # form carry the selection forward.
  def to_params
    {q: q.presence, status: statuses.presence, assignee: assignees.presence, accession: accession_state}.compact
  end

  private

  def search(scope)
    return scope if q.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"

    scope.where('sample_name ILIKE :pattern OR organism ILIKE :pattern OR accession ILIKE :pattern', pattern:)
  end

  def by_status(scope)
    statuses.any? ? scope.where(status: statuses) : scope
  end

  def by_assignee(scope)
    return scope if assignees.empty?

    ids = assignees.map(&:to_i).reject(&:zero?)

    if assignees.include?('0')
      ids.any? ? scope.where(assignee_id: [nil, *ids]) : scope.where(assignee_id: nil)
    else
      scope.where(assignee_id: ids)
    end
  end

  def by_accession(scope)
    case accession_state
    when 'issued'     then scope.where.not(accession: nil)
    when 'not_issued' then scope.where(accession: nil)
    else                   scope
    end
  end
end
