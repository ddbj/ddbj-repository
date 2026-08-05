# What a press of Regenerate would cover, worked out before it is
# pressed.
#
# The form used to be answered only by pressing it: leaving every field
# blank targeted every submission in the database, and the count arrived
# in the flash afterwards. This reads the same parameters the POST will
# and reports the count, the options in the words of their outcome, and
# every number that will not be regenerated — so the screen can say all
# of it while there is still time to change the input.
class RegenerationScope
  DATE_MODES = %w[keep set].freeze

  attr_reader :numbers_text, :date_mode, :date_input, :force, :retry_of

  # Flatfiles are rendered from v1/v2 DDBJ Records. Every BioProject and
  # BioSample record is v3, which has no renderer yet —
  # RegenerateSubmissionFlatfilesJob raises V3NotImplementedError on
  # sight of one. Including them would enqueue thousands of jobs whose
  # only possible outcome is a failed row, so they are named as out of
  # scope here instead.
  def self.regeneratable = Submission.st26_db.where.associated(:ddbj_record_attachment)

  def self.retrying(run)
    new({date_mode: run.locus_date ? 'set' : 'keep', date: run.locus_date&.to_s, force: run.force}, retry_of: run)
  end

  def initialize(params = {}, retry_of: nil)
    @retry_of     = retry_of
    @target       = params[:target].to_s.presence_in(%w[accessions all]) || 'accessions'
    @numbers_text = params[:numbers].to_s
    @date_mode    = params[:date_mode].to_s.presence_in(DATE_MODES) || 'keep'
    @date_input   = params[:date].to_s
    @force        = ActiveModel::Type::Boolean.new.cast(params[:force]) || false
  end

  def target = retry_of ? 'retry' : @target

  def all_target? = target == 'all'

  def retry_target? = target == 'retry'

  def accessions_target? = target == 'accessions'

  def numbers = @numbers ||= numbers_text.split(/[\s,]+/).reject(&:blank?).uniq

  def submissions
    @submissions ||=
      case target
      when 'all'   then self.class.regeneratable
      when 'retry' then self.class.regeneratable.where(id: retry_of.failures.select(:submission_id))
      else              self.class.regeneratable.where(id: Accession.where(number: numbers).select(:submission_id))
      end
  end

  def total = @total ||= submissions.count

  def setting_date? = date_mode == 'set'

  def locus_date
    return nil unless setting_date?

    @locus_date ||= begin
      Date.parse(date_input)
    rescue Date::Error
      nil
    end
  end

  # Numbers that name a record this tool cannot rebuild. Worth telling
  # apart from a typo: a curator who pastes a BioProject accession has
  # not made a mistake, they have asked for something that does not exist
  # yet.
  def out_of_scope
    @out_of_scope ||= begin
      rest = numbers - matched_numbers

      rest & (Project.where(accession: rest).pluck(:accession) + Sample.where(accession: rest).pluck(:accession))
    end
  end

  def unmatched = numbers - matched_numbers - out_of_scope

  # Everything standing between this form and a run, in the order a
  # curator would fix it. The number-shaped ones are silent unless the
  # numbers are what is being run: a list left in the box while the
  # every-submission option is chosen is not a problem, it is a draft.
  def problems
    [
      ('Pick a LOCUS date, or keep the existing ones.' if setting_date? && locus_date.nil?),
      *(numbers_problems if accessions_target?)
    ].compact
  end

  def ready? = total.positive? && !(setting_date? && locus_date.nil?)

  def source_label
    case target
    when 'all'   then 'every ST.26 submission with a stored record'
    when 'retry' then "the #{'failure'.pluralize(retry_of.failed)} from run ##{retry_of.id}"
    else              "from #{numbers.size} #{'accession number'.pluralize(numbers.size)}"
    end
  end

  # The subset of the form the confirmation and the POST have to carry
  # forward — the parameters, not the counts, so that what is confirmed
  # is re-resolved rather than trusted from a link.
  def to_params
    {target: @target, numbers: numbers_text, date_mode:, date: date_input, force: force ? '1' : '0'}
  end

  private

  def numbers_problems
    [
      ("#{unmatched.size} #{'number'.pluralize(unmatched.size)} matched no submission: #{unmatched.take(3).join(', ')}#{'…' if unmatched.size > 3}" if unmatched.any?),
      ("No flatfile for #{out_of_scope.size} #{'number'.pluralize(out_of_scope.size)} — BioProject and BioSample records have none: #{out_of_scope.take(3).join(', ')}" if out_of_scope.any?),
      ('Nothing to regenerate.' if numbers.empty?)
    ]
  end

  def matched_numbers
    @matched_numbers ||= Accession.where(number: numbers, submission: self.class.regeneratable).pluck(:number)
  end
end
