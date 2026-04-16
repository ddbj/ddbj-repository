class ApplySubmissionUpdateJob < ApplicationJob
  include SubmissionOutputWriter

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

    updated_accessions_by_number = ActiveRecord::Base.transaction {
      update.submission.accessions.upsert_all(changed_entries.map {|entry|
        acc = accessions_by_number.fetch(entry.accession)

        {
          **acc.attributes,
          entry_id:        entry.id,
          version:         acc.version.succ,
          locus_date: now.to_date
        }
      }, **{
        unique_by: :number,
        returning: %i[number version locus_date]
      }).index_by {
        it['number']
      }.transform_values(&:deep_symbolize_keys)
    }

    user = update.submission.request.user

    AccessionHistory.insert_all! changed_entries.map {|entry|
      {
        accession_id: accessions_by_number.fetch(entry.accession).id,
        user_id:      user.id,
        action:       'update'
      }
    }

    new_entries = new_entries.map {|entry|
      attrs = updated_accessions_by_number[entry.accession]

      if attrs
        attrs => {version:, locus_date:}

        entry.with(
          version:,
          last_updated: locus_date.to_s
        )
      else
        entry
      end
    }

    new_record = new_record.with(sequences: new_record.sequences.with(entries: new_entries))

    generate_outputs new_record, new_entries, **{
      filename:     update.ddbj_record.filename,
      content_type: update.ddbj_record.content_type
    } do |updates|
      update.submission.update! updates
    end
  end
end
