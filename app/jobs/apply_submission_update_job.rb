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
    old_json = update.submission.ddbj_record.download
    new_json = update.ddbj_record.download

    raise NoChange if old_json == new_json

    old_record = JSON.parse(old_json, symbolize_names: true)
    new_record = JSON.parse(new_json, symbolize_names: true)

    old_entries_by_accession = old_record.dig(:sequence, :entries).index_by { it[:accession] }
    new_entries              = new_record.dig(:sequence, :entries)
    changed_entries          = new_entries.reject { it == old_entries_by_accession[it[:accession]] }
    accessions_by_number     = update.submission.accessions.index_by(&:number)
    now                      = Time.current

    ActiveRecord::Base.transaction do
      updated_accessions_by_number = update.submission.accessions.upsert_all(changed_entries.map {|entry|
        acc = accessions_by_number.fetch(entry[:accession])

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

      new_entries.each do |entry|
        next unless attrs = updated_accessions_by_number[entry[:accession]]

        attrs => {version:, last_updated_at:}

        entry.update(
          version:,
          last_updated: last_updated_at.iso8601
        )
      end

      update.submission.update! ddbj_record: {
        io:           StringIO.new(JSON.pretty_generate(new_record)),
        filename:     update.ddbj_record.filename,
        content_type: update.ddbj_record.content_type
      }
    end
  end
end
