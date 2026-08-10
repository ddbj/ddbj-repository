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

  attr_reader :numbers_text, :date_mode, :date_input, :retry_of

  # Flatfiles are rendered from v1/v2 DDBJ Records, and every BioProject
  # and BioSample record in this system is v3 —
  # RegenerateSubmissionFlatfilesJob raises V3NotImplementedError on
  # sight of one. Including them would enqueue thousands of jobs whose
  # only possible outcome is a failed row, so they are named as out of
  # scope here instead.
  #
  # `db` and not the record's own version, because the version is inside
  # the blob: `submissions.canonical_version` is the canonicaliser's
  # version, a different axis entirely. So this is the closest thing to
  # the question that can be asked in SQL, and an ST.26 submission
  # holding a v3 record still fails — visibly, as a failure row naming
  # it, rather than silently.
  def self.regeneratable = Submission.st26_db.where.associated(:ddbj_record_attachment)

  # The numbers come along too, so a retry dates what the run it is
  # retrying dated. Without them a retry of a run named by accession
  # would fall back to "every entry", and quietly move dates the original
  # had deliberately left alone.
  def self.retrying(run)
    new({date_mode: run.locus_date ? 'set' : 'keep', date: run.locus_date&.to_s, numbers: run.numbers}, retry_of: run)
  end

  def initialize(params = {}, retry_of: nil)
    @retry_of     = retry_of
    @target       = params[:target].to_s.presence_in(%w[accessions all]) || 'accessions'
    @numbers_text = params[:numbers].to_s
    @date_mode    = params[:date_mode].to_s.presence_in(DATE_MODES) || 'keep'
    @date_input   = params[:date].to_s
  end

  def target = retry_of ? 'retry' : @target

  def all_target? = target == 'all'

  def accessions_target? = target == 'accessions'

  def numbers = @numbers ||= numbers_text.split(/[\s,]+/).reject(&:blank?).uniq

  def submissions
    @submissions ||=
      case target
      when 'all'   then self.class.regeneratable
      when 'retry' then self.class.regeneratable.where(id: retry_of.failures.select(:submission_id))
      else              self.class.regeneratable.where(id: Entry.where(accession: numbers).select(:submission_id))
      end
  end

  def total = @total ||= submissions.count

  # Whether the run has an opinion about which entries take the date.
  #
  # A flatfile belongs to a submission, so any of these runs rewrites
  # whole files; the date belongs to the entry, and only a run that named
  # entries knows which ones are meant. A retry of an every-submission
  # run has no numbers to carry, and dating every entry is what that run
  # did.
  def naming_accessions? = !all_target? && numbers.any?

  # Which of the named numbers this submission holds — the argument that
  # tells its job whose dates to move. Nil is every entry, and only the
  # scope that named nothing may say it: a submission that holds none of
  # the named numbers takes an empty list, not a licence to date the lot.
  # The two cannot diverge on the accessions target, where the
  # submissions come from these very numbers, but a retry's submissions
  # come from what failed and nothing keeps the two in step.
  def accessions_for(submission)
    numbers_by_submission.fetch(submission.id, []) if naming_accessions?
  end

  # Whose dates move, in the words of the choice that decided it.
  def dated_label
    return 'every entry' unless naming_accessions?

    "the #{numbers.size} #{'accession'.pluralize(numbers.size)} named"
  end

  def setting_date? = date_mode == 'set'

  def locus_date
    return nil unless setting_date?

    # The same rule the record and the rake options are held to: `Date.parse`
    # would read `8/13` as this year's 13 August, and the form writes this value
    # onto published flatfiles. The field is a date picker, so a browser sends
    # `YYYY-MM-DD` anyway — this is about everything that is not one.
    @locus_date ||= begin
      Date.iso8601(date_input) if date_input.match?(DDBJRecord::LOCUS_DATE_FORMAT)
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

  def unmatched = @unmatched ||= numbers - matched_numbers - out_of_scope

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

  # The subset of the form the confirmation has to carry forward — the
  # parameters, not the counts, so that what is confirmed is re-resolved
  # rather than trusted from a link.
  #
  # The accession list is left out when it is not what is being run: it
  # is a bulk paste of thousands of numbers, and the confirmation is
  # reached by a GET.
  def to_params
    {target: @target, date_mode:, date: date_input}.tap {|params|
      params[:numbers] = numbers_text if accessions_target?
    }
  end

  private

  def numbers_problems
    [
      ("#{unmatched.size} #{'number'.pluralize(unmatched.size)} matched no submission: #{unmatched.take(3).join(', ')}#{'…' if unmatched.size > 3}" if unmatched.any?),
      ("No flatfile for #{out_of_scope.size} #{'number'.pluralize(out_of_scope.size)} — BioProject and BioSample records have none: #{out_of_scope.take(3).join(', ')}" if out_of_scope.any?),
      ('Nothing to regenerate.' if numbers.empty?)
    ]
  end

  # Which of the named numbers each submission holds. One query for the
  # whole run, rather than one per job enqueued — a bulk paste is
  # thousands of numbers, and they arrive as one list.
  def numbers_by_submission
    @numbers_by_submission ||=
      Entry.where(accession: numbers, submission: self.class.regeneratable)
           .pluck(:submission_id, :accession)
           .group_by(&:first)
           .transform_values { it.map(&:last) }
  end

  def matched_numbers = @matched_numbers ||= numbers_by_submission.values.flatten
end
