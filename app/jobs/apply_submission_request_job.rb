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

    ActiveRecord::Base.transaction do |tx|
      na_nums    = Sequence.allocate!(:jpo_na, na_entries.size)
      aa_nums    = Sequence.allocate!(:jpo_aa, aa_entries.size)
      submission = request.create_submission!

      entry_id_to_attrs = submission.accessions.insert_all(entries.map {|entry|
        {
          number:   (aa?(entry) ? aa_nums : na_nums).shift,
          entry_id: entry.id
        }
      }, **{
        unique_by: :number,
        returning: %i[entry_id number version last_updated_at]
      }).index_by {
        it['entry_id']
      }.transform_values(&:deep_symbolize_keys)

      entries = entries.map {|entry|
        entry_id_to_attrs.fetch(entry.id) => {number: accession, version:, last_updated_at:}

        entry.with(
          accession:,
          locus:        accession,
          version:,
          last_updated: last_updated_at.iso8601
        )
      }

      record      = record.with(sequences: record.sequences.with(entries:))
      ddbj_record = DDBJRecord.generate(record)
      filename    = request.ddbj_record.filename

      submission.update! ddbj_record: {
        io:           ddbj_record,
        filename:,
        content_type: request.ddbj_record.content_type
      }

      aa_entries, na_entries = entries.partition { aa?(it) }

      unless na_entries.empty?
        flatfile_na = Flatfile.render(record, na_entries)

        submission.update! flatfile_na: {
          io:           flatfile_na,
          filename:     "#{filename.base}-na.flat",
          content_type: 'text/plain'
        }
      end

      unless aa_entries.empty?
        flatfile_aa = Flatfile.render(record, aa_entries)

        submission.update! flatfile_aa: {
          io:           flatfile_aa,
          filename:     "#{filename.base}-aa.flat",
          content_type: 'text/plain'
        }
      end

      tx.after_commit do
        ddbj_record.close!
        flatfile_na&.close!
        flatfile_aa&.close!
      end
    end
  end

  def aa?(entry)
    Array(entry.source_qualifiers['mol_type']).any? { it.value == 'protein' }
  end
end
