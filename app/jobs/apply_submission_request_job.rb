class ApplySubmissionRequestJob < ApplicationJob
  include SubmissionOutputWriter

  def perform(request)
    request.applying!

    apply request
  rescue => e
    Rails.error.report e

    request.update!(
      status:        :application_failed,
      error_message: e.message
    )
  else
    request.applied!
  end

  private

  def apply(request)
    request.ddbj_record.open do |file|
      parser             = DDBJRecord::StreamingParser.new(file.path)
      metadata           = parser.metadata
      features_by_seq_id = parser.features_by_sequence_id
      all_features       = features_by_seq_id.values.flatten

      # Pass 1: Collect entry IDs and types (sequences are discarded by GC)
      entry_metas = parser.each_entry.map {|entry|
        {id: entry.id, is_aa: aa?(entry)}
      }

      na_count = entry_metas.count { !it[:is_aa] }
      aa_count = entry_metas.count { it[:is_aa] }

      na_nums, aa_nums, submission = ActiveRecord::Base.transaction {
        [
          Sequence.allocate!(:jpo_na, na_count),
          Sequence.allocate!(:jpo_aa, aa_count),
          request.create_submission!
        ]
      }

      now              = Time.current
      ts               = now.utc.iso8601(6)
      entry_accessions = {}
      conn             = ActiveRecord::Base.connection.raw_connection

      conn.copy_data('COPY accessions (number, entry_id, submission_id, version, last_updated_at, created_at, updated_at) FROM STDIN') do
        entry_metas.each do |meta|
          number = (meta[:is_aa] ? aa_nums : na_nums).shift

          entry_accessions[meta[:id]] = number

          conn.put_copy_data "#{number}\t#{meta[:id]}\t#{submission.id}\t1\t#{ts}\t#{ts}\t#{ts}\n"
        end
      end

      # Pass 2: Stream entries → JSON + flatfiles
      record = metadata.with(features: all_features)

      entries = parser.each_entry.lazy.map {|entry|
        accession = entry_accessions.fetch(entry.id)

        entry.with(
          accession:,
          locus:        accession,
          version:      1,
          last_updated: entry.last_updated || now.iso8601
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
