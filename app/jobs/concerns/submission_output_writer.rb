module SubmissionOutputWriter
  private

  # The outputs, uploaded, and then the pointers swapped inside the caller's
  # transaction.
  #
  # Handing the payloads to `update!` instead put the upload in an
  # `after_commit`, so a storage failure left the row pointing at a blob whose
  # bytes were never written — and because the row carries the checksum of what
  # *should* be there, the next run generates the same bytes, compares equal, and
  # skips. The byteless blob is then permanent, and nothing says so: the
  # LocusDateDisagreement guard reads dates, and here the dates are right.
  #
  # Uploading first means a failure there raises before anything is written, and
  # a failure in the transaction leaves blobs nobody points at — purged, the way
  # Submission#prime_cache! does it.
  #
  # `nil` for an output is preserved: it means "there is no such file", and
  # assigning nil is what detaches the one that is there (an AA flatfile that no
  # longer has any AA entries).
  def write_outputs!(submission, outputs)
    blobs = outputs.transform_values { it && ActiveStorage::Blob.create_and_upload!(**it) }

    begin
      ActiveRecord::Base.transaction do
        yield if block_given?

        submission.update! blobs
      end
    rescue StandardError
      blobs.each_value { it&.purge_later }

      raise
    end
  end

  # `flatfile_omits` is entry ids the flatfile leaves out — canceled and
  # withdrawn entries. They stay in the DDBJ Record, which is the account
  # of what was submitted; the flatfile is what goes out, and a withdrawn
  # entry going out is the thing withdrawing it was for. Dropping them
  # from `entries` instead would take them out of both.
  def generate_outputs(record, entries, filename:, content_type:, flatfile_omits: Set.new)
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

        next if flatfile_omits.include?(entry.id)

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
