class DRASubmission < ApplicationRecord
  include Lifecycleable

  # SRA for the 27 early submissions D-way numbers under that prefix.
  ACCESSION_FORMAT = /\A[DS]RA\d{6,}\z/

  belongs_to :submission

  validates :accession, format: {with: ACCESSION_FORMAT}, allow_nil: true

  # None for one imported from D-way until it has handed over
  # (DwayTakeover): its status is D-way's until then, and the next import
  # would put back a status set here. One sent here is curated here.
  def self.settable_statuses_for(rows)
    return settable_statuses if DwayTakeover.done?

    rows.joins(:submission).where.not(submissions: {source_id: nil}).exists? ? [] : settable_statuses
  end

  # What its public documents would not be valid as, for each submission
  # refused publication: nothing is made public of any of them. The
  # message is the whole of it, a line a submission, for the error report;
  # a screen says `summary`, since the flash lives in a 4 KB cookie and the
  # XSD's message for a wrong value lists every value it takes.
  class Unpublishable < StandardError
    SUMMARY_REASON = 300

    attr_reader :refusals

    def initialize(refusals)
      @refusals = refusals

      super(refusals.map { "#{_1}: #{_2}" }.join("\n"))
    end

    # Which ones, and the first reason — enough to open it and look.
    def summary
      names, reasons = refusals.transpose
      more           = " (and #{(reasons.size - 1).to_fs(:delimited)} more)" if reasons.size > 1

      "#{names.first(10).join(', ')}#{', …' if names.size > 10}: #{reasons.first.truncate(SUMMARY_REASON)}#{more}"
    end
  end

  # Published, a DRA submission takes along what its experiments are part
  # of (DRA::LinkedRelease) — however it is published, by its hold date or
  # by a curator.
  #
  # And only if what it publishes can be: its public documents valid as
  # the version D-way published in (PublicXML::DRA::Documents). D-way kept
  # one that was not private until it was, rather than call it public and
  # publish nothing — or tell its submitter it was public.
  def self.move_to_status!(status, **)
    return super unless status.to_s == 'public'

    transaction do
      publishing = where.not(status: :public).lock.order(:id).pluck(:submission_id)
      refuse_unpublishable! publishing
      count      = super

      Submission.where(id: publishing).find_each { DRA::LinkedRelease.call(it) }

      count
    end
  end

  def self.refuse_unpublishable!(submission_ids)
    refusals = Submission.where(id: submission_ids).includes(:dra_submission).find_each.filter_map { refusal(it) }

    raise Unpublishable, refusals if refusals.any?
  end

  # [what the submission is called, why] where it cannot be published.
  def self.refusal(submission)
    name   = submission.dra_submission.accession || submission.source_id || "##{submission.id}"
    record = submission.materialised_record or return [name, 'it has no record to publish']

    PublicXML::DRA::Documents.call(record)

    nil
  rescue PublicXML::DRA::Documents::Invalid => e
    [name, e.message]
  end

  private_class_method :refuse_unpublishable!, :refusal
end
