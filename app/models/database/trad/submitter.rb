class Database::Trad::Submitter
  def submit(submission)
    validation = submission.validation

    return unless validation.via_ddbj_record?

    obj     = validation.objs.find_by!(_id: 'DDBJRecord')
    record  = JSON.parse(obj.file.download, symbolize_names: true)
    entries = record.dig(:sequence, :entries)

    ActiveRecord::Base.transaction do
      start_num = Sequence.claim('accessions.number/AB', count: entries.size)

      entry_id_to_attrs = submission.accessions.insert_all(entries.map.with_index {|entry, i|
        {
          number:   "AB#{(start_num + i).to_s.rjust(6, '0')}",
          entry_id: entry[:id]
        }
      }, **{
        unique_by: %i[number entry_id version],
        returning: %i[entry_id number version last_updated_at]
      }).index_by { it['entry_id'] }.transform_values(&:deep_symbolize_keys)

      entries.each do |entry|
        entry_id_to_attrs.fetch(entry[:id]) => {number: accession, version:, last_updated_at:}

        entry.update(
          accession:,
          locus:        accession,
          version:,
          last_updated: Time.zone.parse(last_updated_at).iso8601
        )
      end
    end

    puts JSON.pretty_generate(record)
  end
end
