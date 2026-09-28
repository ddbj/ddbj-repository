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

  def call
    @request.ddbj_record.open do |file|
      # StreamingParser is v2-shaped (SAJ only) and would fail downstream as a
      # NoMethodError.
      DDBJRecord.refuse_v3! file, "SubmissionRequest ##{@request.id}"

      parser             = DDBJRecord::StreamingParser.new(file.path)
      metadata           = parser.metadata
      features_by_seq_id = parser.features_by_sequence_id
      all_features       = features_by_seq_id.values.flatten

      now   = Time.current
      today = now.to_date
      ts    = now.utc.iso8601(6)

      # Pass 1: Collect entry IDs, types and LOCUS dates (sequences are
      # discarded by GC)
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
      entry_metas = parser.each_entry.map {|entry|
        {id: entry.id, is_aa: aa?(entry), locus_date: locus_date_for(entry, today)}
      }

      na_count = entry_metas.count { !it[:is_aa] }
      aa_count = entry_metas.count { it[:is_aa] }

      na_nums, aa_nums, submission = ActiveRecord::Base.transaction {
        [
          Sequence.allocate!(:jpo_na, na_count),
          Sequence.allocate!(:jpo_aa, aa_count),
          @request.create_submission!(db: @request.db, user: @request.user)
        ]
      }

      entry_accessions = {}
      entry_dates      = {}
      conn             = ActiveRecord::Base.connection.raw_connection

      conn.copy_data('COPY entries (accession, entry_id, submission_id, version, locus_date, created_at, updated_at) FROM STDIN') do
        entry_metas.each do |meta|
          number = (meta[:is_aa] ? aa_nums : na_nums).shift

          entry_accessions[meta[:id]] = number
          entry_dates[meta[:id]]      = meta[:locus_date]

          conn.put_copy_data "#{number}\t#{meta[:id]}\t#{submission.id}\t1\t#{meta[:locus_date]}\t#{ts}\t#{ts}\n"
        end
      end

      EntryHistory.insert_all! submission.entries.ids.map {|id|
        {
          entry_id: id,
          user_id:      @request.user_id,
          action:       'create'
        }
      }

      # Pass 2: Stream entries → JSON + flatfiles
      record = metadata.with(features: all_features)

      entries = parser.each_entry.lazy.map {|entry|
        accession = entry_accessions.fetch(entry.id)

        # The same date that went into the column, not the record's own string:
        # one value, normalised once, so the flatfile and `entries.locus_date`
        # cannot come apart.
        entry.with(
          accession:,
          locus:      accession,
          version:    1,
          locus_date: entry_dates.fetch(entry.id).to_s
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
