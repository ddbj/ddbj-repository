# Applying an ST.26 record (v2): each entry is numbered from the JPO
# scopes as it streams past, and the record and its flatfiles are written
# with the numbers in. The record is read twice rather than held — a file
# can run to tens of thousands of entries.
class SubmissionApply::St26
  include SubmissionOutputWriter

  class MalformedLocusDate < StandardError; end

  def self.call(request) = new(request).call

  def initialize(request)
    @request = request
  end

  # Run again after it was stopped part way (RecoverKilledJobsJob), it
  # carries on from what it committed: the numbers, the submission and its
  # entries are one commit, and the outputs the next. A submission with its
  # record written is done; one without keeps its numbers, and only the
  # outputs are written again — as they are for a request sent again after
  # writing them failed.
  def call
    return if @request.submission&.ddbj_record&.attached?

    @request.ddbj_record.open do |file|
      # StreamingParser is v2-shaped (SAJ only) and would fail downstream as a
      # NoMethodError.
      DDBJRecord.refuse_v3! file, "SubmissionRequest ##{@request.id}"

      parser     = DDBJRecord::StreamingParser.new(file.path)
      submission = @request.submission || number!(parser)
      numbered   = submission.entries.pluck(:entry_id, :accession, :locus_date).to_h { [it[0], it[1..]] }

      # Pass 2: Stream entries → JSON + flatfiles
      record = parser.metadata.with(features: parser.features_by_sequence_id.values.flatten)

      entries = parser.each_entry.lazy.map {|entry|
        accession, locus_date = numbered.fetch(entry.id)

        # The date that went into the column, not the record's own string:
        # one value, normalised once, so the flatfile and `entries.locus_date`
        # cannot come apart.
        entry.with(
          accession:,
          locus:      accession,
          version:    1,
          locus_date: locus_date.to_s
        )
      }

      generate_outputs record, entries, **{
        filename:     @request.ddbj_record.filename,
        content_type: @request.ddbj_record.content_type
      } do |outputs|
        write_outputs! submission, outputs
      end
    end
  end

  private

  # Pass 1: Collect entry IDs, types and LOCUS dates (sequences are discarded
  # by GC), and number them — in one commit with the submission and its
  # entries, so the numbers are never allocated to nothing.
  #
  # The sequence rows stay locked until that commit, so ST.26 applies running
  # side by side wait on each other for the length of the COPY — seconds,
  # for tens of thousands of entries. Committing the numbers first is what
  # let a run stopped in between number its entries again.
  #
  # `today` is only a stand-in for a record that names no date. It used to be
  # written unconditionally into `entries.locus_date` while the flatfile
  # printed the record's own date, so the column and the flatfile disagreed
  # from the moment a submission was applied — and any later regeneration,
  # which renders from the column, pulled the printed date back to the apply
  # date. The date belongs to whoever performed the publication, so the
  # record is where it comes from.
  #
  # Normalised to a Date once, so the column and the record cannot spell the
  # same day two ways.
  def number!(parser)
    now   = Time.current
    today = now.to_date
    ts    = now.utc.iso8601(6)

    entry_metas = parser.each_entry.map {|entry|
      {id: entry.id, is_aa: aa?(entry), locus_date: locus_date_for(entry, today)}
    }

    ActiveRecord::Base.transaction do
      na_nums = Sequence.allocate!(:jpo_na, entry_metas.count { !it[:is_aa] })
      aa_nums = Sequence.allocate!(:jpo_aa, entry_metas.count { it[:is_aa] })

      submission = Submission.create!(db: @request.db, user: @request.user)

      # Said outright: assigning the association saves the request only
      # through autosave, which drops the write silently when the request's
      # own validations fail — and a request with no submission is applied
      # from the start again, numbered twice.
      @request.update_columns submission_id: submission.id

      conn = ActiveRecord::Base.connection.raw_connection

      conn.copy_data('COPY entries (accession, entry_id, submission_id, version, locus_date, created_at, updated_at) FROM STDIN') do
        entry_metas.each do |meta|
          number = (meta[:is_aa] ? aa_nums : na_nums).shift

          conn.put_copy_data "#{number}\t#{meta[:id]}\t#{submission.id}\t1\t#{meta[:locus_date]}\t#{ts}\t#{ts}\n"
        end
      end

      EntryHistory.insert_all! submission.entries.ids.map {|id|
        {
          entry_id: id,
          user_id:  @request.user_id,
          action:   'create'
        }
      }

      submission
    end
  end

  # The date the publication operator put on this entry, or `fallback` when the
  # record names none.
  #
  # Refused rather than guessed, against DDBJRecord::LOCUS_DATE_FORMAT — the rule
  # the Regenerate form and the backfill are held to as well, so one format
  # covers every way a LOCUS date can be set. Refusing costs nothing here: pass 1
  # runs before any accession is allocated.
  def locus_date_for(entry, fallback)
    given = entry.locus_date.presence or return fallback

    # `to_s`, so a JSON number (`"locus_date": 20260813`) is refused with this
    # code rather than raising NoMethodError into the TRD_R9999 catch-all.
    raise MalformedLocusDate, %(#{entry.id}: locus_date "#{given}" is not written as YYYY-MM-DD) unless given.to_s.match?(DDBJRecord::LOCUS_DATE_FORMAT)

    begin
      Date.iso8601(given)
    rescue Date::Error
      raise MalformedLocusDate, %(#{entry.id}: locus_date "#{given}" is not a real date)
    end
  end
end
