# Narrows a submission's rows down to "the group I am fixing right now".
#
# A BioSample submission can carry 100K samples and an ST.26 one 27K
# entries, so neither screen is usable without this: the curator never
# wants the whole bag, they want the ones still being curated, or the ones
# whose name matches something.
#
# The same object backs the list and the bulk action, so "apply to all
# rows matching the filter" re-derives the target set server-side from the
# posted filter rather than trusting a client-supplied id list — which is
# the only way that button can mean what it says at 100K rows.
#
# Subclasses say which columns the free-text box searches, and add any
# filter that is theirs alone. Everything a row has by virtue of being a
# curation row — the Lifecycleable status — is here.
class SubmissionRowSearch
  class << self
    # Columns the free-text box matches, ILIKE, any of them.
    def search_columns(*columns)
      @search_columns = columns.map(&:to_s) if columns.any?
      @search_columns || []
    end

    # The model, so the status filter can check the value against the
    # enum rather than passing anything through to the WHERE.
    def model = name.delete_suffix('Search').constantize
  end

  def initialize(relation, params)
    @relation = relation
    @params   = params
  end

  def scope = steps.reduce(@relation) {|scope, step| send(step, scope) }

  def q = @params[:q].to_s.strip

  def statuses = @statuses ||= Array(@params[:status]).map(&:to_s) & self.class.model.statuses.keys

  def active? = q.present? || statuses.any?

  # The current filter as query params, so pagination links and the bulk
  # form carry the selection forward.
  def to_params = {q: q.presence, status: statuses.presence}.compact

  private

  def steps = %i[search by_status]

  def search(scope)
    return scope if q.blank?

    columns = self.class.search_columns
    return scope if columns.empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    sql     = columns.map { "#{scope.klass.quoted_table_name}.#{scope.klass.connection.quote_column_name(it)} ILIKE :pattern" }

    scope.where(sql.join(' OR '), pattern:)
  end

  def by_status(scope) = statuses.any? ? scope.where(status: statuses) : scope
end
