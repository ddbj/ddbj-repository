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
    record  = request.ddbj_record.open { DDBJRecord.parse(it) }
    entries = record.sequences.entries

    aa_entries, na_entries = entries.partition { aa?(it) }

    na_nums, aa_nums, submission = ActiveRecord::Base.transaction {
      [
        Sequence.allocate!(:jpo_na, na_entries.size),
        Sequence.allocate!(:jpo_aa, aa_entries.size),
        request.create_submission!
      ]
    }

    now              = Time.current
    ts               = now.utc.iso8601(6)
    entry_accessions = {}
    conn             = ActiveRecord::Base.connection.raw_connection

    conn.copy_data('COPY accessions (number, entry_id, submission_id, version, last_updated_at, created_at, updated_at) FROM STDIN') do
      entries.each do |entry|
        number = (aa?(entry) ? aa_nums : na_nums).shift
        entry_accessions[entry.id] = number

        conn.put_copy_data "#{number}\t#{entry.id}\t#{submission.id}\t1\t#{ts}\t#{ts}\t#{ts}\n"
      end
    end

    entries = entries.map {|entry|
      accession = entry_accessions.fetch(entry.id)

      entry.with(
        accession:,
        locus:        accession,
        version:      1,
        last_updated: now.iso8601
      )
    }

    record      = record.with(sequences: record.sequences.with(entries:))
    ddbj_record = DDBJRecord.generate(record)
    filename    = request.ddbj_record.filename

    updates = {
      ddbj_record: {
        io:           ddbj_record,
        filename:,
        content_type: request.ddbj_record.content_type
      }
    }

    aa_entries, na_entries = entries.partition { aa?(it) }

    unless na_entries.empty?
      flatfile_na = Flatfile.render(record, na_entries)

      updates[:flatfile_na] = {
        io:           flatfile_na,
        filename:     "#{filename.base}-na.flat",
        content_type: 'text/plain'
      }
    end

    unless aa_entries.empty?
      flatfile_aa = Flatfile.render(record, aa_entries)

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

  def aa?(entry)
    entry.source_features.any? { it.source&.mol_type == 'protein' }
  end
end
