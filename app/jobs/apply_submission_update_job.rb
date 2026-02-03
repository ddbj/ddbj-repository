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
    old_record  = JSON.parse(update.submission.ddbj_record.download, symbolize_names: true)
    new_record  = JSON.parse(update.ddbj_record.download, symbolize_names: true)
    old_entries = old_record.dig(:sequence, :entries).index_by { it[:accession] }
    new_entries = new_record.dig(:sequence, :entries)

    changes = new_entries.select {|new_entry|
      old_entry = old_entries.fetch(new_entry[:accession])

      new_entry != old_entry
    }

    raise NoChange if changes.empty?

    ActiveRecord::Base.transaction do
      number_to_accession = update.submission.accessions.index_by(&:number)
      now                 = Time.current

      accession_to_attrs = update.submission.accessions.upsert_all(changes.map {|entry|
        acc = number_to_accession.fetch(entry[:accession])

        {
          **acc.attributes,
          entry_id:        entry[:id],
          version:         acc.version.succ,
          last_updated_at: now
        }
      }, **{
        unique_by: :number,
        returning: %i[number version last_updated_at]
      }).index_by {
        it['number']
      }.transform_values(&:deep_symbolize_keys)

      entries.each do |entry|
        next unless attrs = accession_to_attrs[entry[:accession]]

        attrs => {version:, last_updated_at:}

        entry.update(
          version:,
          last_updated: Time.zone.parse(last_updated_at).iso8601
        )
      end

      update.submission.update! ddbj_record: {
        io:           StringIO.new(JSON.pretty_generate(record)),
        filename:     update.ddbj_record.filename,
        content_type: update.ddbj_record.content_type
      }
    end
  end
end
