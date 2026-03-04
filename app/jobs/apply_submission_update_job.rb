class ApplySubmissionUpdateJob < ApplicationJob
  class NoChange < StandardError; end

  def perform(update)
    update.applying!

    begin
      apply update
    rescue NoChange
      update.no_change!
    rescue => e
      Rails.error.report e

      update.update!(
        status:        :application_failed,
        error_message: e.message
      )
    else
      update.applied!
    end
  end

  private

  def apply(update)
    raise NoChange if update.submission.ddbj_record.checksum == update.ddbj_record.checksum

    old_record = update.submission.ddbj_record.open { DDBJRecord.parse(it) }
    new_record = update.ddbj_record.open { DDBJRecord.parse(it) }

    old_entries_by_accession = old_record.sequences.entries.index_by(&:accession)
    new_entries              = new_record.sequences.entries
    changed_entries          = new_entries.reject { it == old_entries_by_accession[it.accession] }
    accessions_by_number     = update.submission.accessions.index_by(&:number)
    now                      = Time.current

    ActiveRecord::Base.transaction do
      updated_accessions_by_number = update.submission.accessions.upsert_all(changed_entries.map {|entry|
        acc = accessions_by_number.fetch(entry.accession)

        {
          **acc.attributes,
          entry_id:        entry.id,
          version:         acc.version.succ,
          last_updated_at: now
        }
      }, **{
        unique_by: :number,
        returning: %i[number version last_updated_at]
      }).index_by {
        it['number']
      }.transform_values(&:deep_symbolize_keys)

      new_entries = new_entries.map {|entry|
        attrs = updated_accessions_by_number[entry.accession]

        if attrs
          attrs => {version:, last_updated_at:}

          entry.with(
            version:,
            last_updated: last_updated_at.iso8601
          )
        else
          entry
        end
      }

      new_record = new_record.with(sequences: new_record.sequences.with(entries: new_entries))

      update.submission.update! ddbj_record: {
        io:           StringIO.new(JSON.pretty_generate(new_record.as_json)),
        filename:     update.ddbj_record.filename,
        content_type: update.ddbj_record.content_type
      }
    end
  end
end
