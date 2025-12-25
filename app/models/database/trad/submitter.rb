class Database::Trad::Submitter
  def submit(submission)
    validation = submission.validation

    return unless validation.via_ddbj_record?

    obj     = validation.objs.find_sole_by(_id: 'DDBJRecord')
    record  = JSON.parse(obj.file.download, symbolize_names: true)
    entries = record.dig(:sequence, :entries)

    aa_count, na_count = entries.partition { aa?(it) }.map(&:size)

    ActiveRecord::Base.transaction do
      na_nums = Sequence.allocate!(:jpo_na, na_count)
      aa_nums = Sequence.allocate!(:jpo_aa, aa_count)

      entry_id_to_attrs = submission.accessions.insert_all(entries.map {|entry|
        {
          number:   (aa?(entry) ? aa_nums : na_nums).shift,
          entry_id: entry[:id]
        }
      }, **{
        unique_by: %i[number entry_id version],
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

      filename = obj.file.filename

      validation.objs.create!(
        _id:         'DDBJRecord',
        validity:    :valid,
        destination: obj.destination,

        file: {
          io:           StringIO.new(JSON.pretty_generate(record)),
          filename:     "#{filename.base}-#{Time.current.iso8601}.#{filename.extension}",
          content_type: obj.file.content_type
        }
      )
    end
  end

  def aa?(entry)
    Array(entry.dig(:source_qualifiers, :mol_type)).any? { it[:value] == 'protein' }
  end
end
