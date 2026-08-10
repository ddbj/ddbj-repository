class ApplySubmissionRequestJob < ApplicationJob
  include SubmissionOutputWriter

  # 分類できた失敗だけがコードを持ち、残りは catch-all になる。増やすときはここに 1 行
  # 足して README の表に書く。クライアントは知らないコードを catch-all と同じに扱えば
  # よいので、追加は常に additive。
  #
  # error_message の方は人間向けで、文言は予告なく変わる。**機械的な判断はコードで
  # 行うこと。**
  class MalformedLocusDate < StandardError; end

  ERROR_CODES = {
    Sequence::Exhausted => 'TRD_R0012',
    MalformedLocusDate  => 'TRD_R0014'
  }.freeze

  UNEXPECTED_ERROR_CODE = 'TRD_R9999'


  def perform(request)
    # 前回の失敗の痕跡を残さない。コードは機械的な判断に使われるので、古い値が
    # 残っていると「今まさに失敗している」と読まれる。
    request.update!(
      status:        :applying,
      error_code:    nil,
      error_message: nil
    )

    apply request
  rescue Exception => e # rubocop:disable Lint/RescueException
    # StandardError 以外（SystemStackError 等）でも必ず終端状態に落とす。
    # ここで取り逃すと request が applying のまま取り残され、クライアントが
    # status を永久にポーリングし続ける。シグナル等は記録だけして上位へ流す。
    Rails.error.report e

    request.update!(
      status:        :application_failed,
      error_code:    error_code_for(e),
      error_message: e.message
    )

    raise unless e.is_a?(StandardError)
  else
    request.applied!
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

  def error_code_for(error)
    _, code = ERROR_CODES.find {|klass, _| error.is_a?(klass) }

    code || UNEXPECTED_ERROR_CODE
  end

  def apply(request)
    request.ddbj_record.open do |file|
      # v3 streaming + apply path is unimplemented — refuse explicitly
      # to prevent silent NoMethodError downstream when
      # DDBJRecord::StreamingParser (v2 SAJ-only) hits v3 input.
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind
      if major == '3'
        raise DDBJRecord::V3NotImplementedError,
              "SubmissionRequest ##{request.id}: v3 record application not yet implemented (Phase 6+)"
      end

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
          request.create_submission!(db: request.db, user: request.user)
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
          user_id:      request.user_id,
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
        filename:     request.ddbj_record.filename,
        content_type: request.ddbj_record.content_type
      } do |updates|
        submission.update! updates
      end
    end
  end
end
