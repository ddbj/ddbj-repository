# A BioSample submission's samples. Adds the one filter that is a
# sample's alone: whether it has an accession yet. An ST.26 entry always
# has one — the number is what the row is created with — so there is
# nothing there to ask about.
class SampleSearch < SubmissionRowSearch
  search_columns :sample_name, :organism, :accession

  FILTER_KEYS = %i[q status accession].freeze

  ACCESSION_STATES = {
    'issued'     => 'Issued',
    'not_issued' => 'Not issued'
  }.freeze

  def accession_state
    ACCESSION_STATES.key?(@params[:accession]) ? @params[:accession] : nil
  end

  def active? = super || accession_state.present?

  def to_params = super.merge({accession: accession_state}.compact)

  private

  def steps = super + %i[by_accession]

  def by_accession(scope)
    case accession_state
    when 'issued'     then scope.where.not(accession: nil)
    when 'not_issued' then scope.where(accession: nil)
    else                   scope
    end
  end
end
