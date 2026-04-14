module SubmissionOutputWriter
  private

  def generate_outputs(record, entries, filename:, content_type:)
    features_by_seq_id = record.features.group_by(&:sequence_id)

    ddbj_record = Tempfile.open(['ddbj_record', '.json'])
    ddbj_record.binmode

    flatfile_na = Tempfile.open(['flatfile-na', '.flat'])
    flatfile_na.binmode

    flatfile_aa = Tempfile.open(['flatfile-aa', '.flat'])
    flatfile_aa.binmode

    na_renderer = Flatfile::StreamingRenderer.new(record, features_by_seq_id, flatfile_na)
    aa_renderer = Flatfile::StreamingRenderer.new(record, features_by_seq_id, flatfile_aa)

    DDBJRecord::StreamingWriter.new(ddbj_record).write record, features: record.features do |w|
      entries.each do |entry|
        w << entry

        if aa?(entry)
          aa_renderer.render_entry entry
        else
          na_renderer.render_entry entry
        end
      end
    end

    ddbj_record.write "\n"
    ddbj_record.rewind

    yield(
      ddbj_record: {
        io:           ddbj_record,
        filename:,
        content_type:
      },

      flatfile_na: flatfile_na.size > 0 ? (flatfile_na.rewind; {
        io:           flatfile_na,
        filename:     "#{filename.base}-na.flat",
        content_type: 'text/plain'
      }) : nil,

      flatfile_aa: flatfile_aa.size > 0 ? (flatfile_aa.rewind; {
        io:           flatfile_aa,
        filename:     "#{filename.base}-aa.flat",
        content_type: 'text/plain'
      }) : nil
    )
  ensure
    ddbj_record&.close!
    flatfile_na&.close!
    flatfile_aa&.close!
  end

  def aa?(entry)
    entry.source_features.any? { it.source&.mol_type == 'protein' }
  end
end
