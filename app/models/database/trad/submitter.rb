class Database::Trad::Submitter
  def submit(submission)
    validation = submission.validation

    return unless validation.via_ddbj_record?

    obj     = validation.objs.find_by!(_id: 'DDBJRecord')
    record  = JSON.parse(obj.file.download, symbolize_names: true)
    entries = record.dig(:sequence, :entries)

    ActiveRecord::Base.transaction do
      start_num = Sequence.claim('accessions.number/AB', count: entries.size)

      submission.accessions.insert_all entries.map.with_index {|entry, i|
        {
          number:   "AB#{(start_num + i).to_s.rjust(6, '0')}",
          entry_id: entry[:id]
        }
      }
    end
  end
end
