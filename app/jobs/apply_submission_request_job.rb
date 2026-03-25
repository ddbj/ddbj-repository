class ApplySubmissionRequestJob < ApplicationJob
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
      ddbj_record = Tempfile.open(['ddbj_record', '.json'])
      ddbj_record.binmode

      flatfile_na = Tempfile.open(['flatfile-na', '.flat'])
      flatfile_na.binmode

      flatfile_aa = Tempfile.open(['flatfile-aa', '.flat'])
      flatfile_aa.binmode

      na_renderer = Flatfile::StreamingRenderer.new(metadata, features_by_seq_id, flatfile_na)
      aa_renderer = Flatfile::StreamingRenderer.new(metadata, features_by_seq_id, flatfile_aa)

      DDBJRecord::StreamingWriter.new(ddbj_record).write(metadata, features: all_features) do |w|
        parser.each_entry do |entry|
          accession = entry_accessions.fetch(entry.id)

          entry = entry.with(
            accession:,
            locus:        accession,
            version:      1,
            last_updated: now.iso8601
          )

          w << entry

          if aa?(entry)
            aa_renderer.render_entry(entry)
          else
            na_renderer.render_entry(entry)
          end
        end
      end

      ddbj_record.write "\n"
      ddbj_record.rewind

      filename = request.ddbj_record.filename

      updates = {
        ddbj_record: {
          io:           ddbj_record,
          filename:,
          content_type: request.ddbj_record.content_type
        }
      }

      if flatfile_na.size > 0
        flatfile_na.rewind

        updates[:flatfile_na] = {
          io:           flatfile_na,
          filename:     "#{filename.base}-na.flat",
          content_type: 'text/plain'
        }
      end

      if flatfile_aa.size > 0
        flatfile_aa.rewind

        updates[:flatfile_aa] = {
          io:           flatfile_aa,
          filename:     "#{filename.base}-aa.flat",
          content_type: 'text/plain'
        }
      end

      submission.update! updates
    ensure
      ddbj_record&.close!
      flatfile_na&.close!
      flatfile_aa&.close!
    end
  end

  def aa?(entry)
    entry.source_features.any? { it.source&.mol_type == 'protein' }
  end
end
