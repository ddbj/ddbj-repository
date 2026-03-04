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
    record  = JSON.parse(request.ddbj_record.download, symbolize_names: true)
    entries = record.dig(:sequences, :entries)

    aa_count, na_count = entries.partition { aa?(it) }.map(&:size)

    ActiveRecord::Base.transaction do |tx|
      na_nums    = Sequence.allocate!(:jpo_na, na_count)
      aa_nums    = Sequence.allocate!(:jpo_aa, aa_count)
      submission = request.create_submission!

      entry_id_to_attrs = submission.accessions.insert_all(entries.map {|entry|
        {
          number:   (aa?(entry) ? aa_nums : na_nums).shift,
          entry_id: entry[:id]
        }
      }, **{
        unique_by: :number,
        returning: %i[entry_id number version last_updated_at]
      }).index_by {
        it['entry_id']
      }.transform_values(&:deep_symbolize_keys)

      entries.each do |entry|
        entry_id_to_attrs.fetch(entry[:id]) => {number: accession, version:, last_updated_at:}

        entry.update(
          accession:,
          locus:        accession,
          version:,
          last_updated: last_updated_at.iso8601
        )
      end

      filename = request.ddbj_record.filename

      submission.update! ddbj_record: {
        io:           StringIO.new(JSON.pretty_generate(record) + "\n"),
        filename:,
        content_type: request.ddbj_record.content_type
      }

      flatfile = Flatfile::Root.new(record, record.dig(:sequences, :entries)).render

      submission.update! flatfile: {
        io:           flatfile,
        filename:     "#{filename.base}.flat",
        content_type: 'text/plain'
      }

      tx.after_commit do
        flatfile.close!
      end
    end
  end

  def aa?(entry)
    Array(entry.dig(:source_qualifiers, :mol_type)).any? { it[:value] == 'protein' }
  end
end
