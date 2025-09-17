class AccessionsController < ApplicationController
  def show
    @accession = current_user.accessions.find_by!(number: params.expect(:number))
  end

  def update
    @accession = current_user.accessions.find_by!(number: params.expect(:number))

    validation     = @accession.submission.validation
    objs           = validation.objs.DDBJRecord
    current_record = JSON.parse(objs.last.file.download, symbolize_names: true)
    current_entry  = current_record.dig(:sequence, :entries).find { it[:id] == @accession.entry_id }
    new_record     = JSON.parse(params.expect(:DDBJRecord).read, symbolize_names: true)

    unless new_entry = new_record.dig(:sequence, :entries).find { it[:id] == @accession.entry_id }
      render json: {
        error: "The provided record does not contain an entry with ID #{@accession.entry_id}."
      }, status: :unprocessable_content

      return
    end

    number       = @accession.number
    version      = @accession.version + 1
    last_updated = Time.current

    current_entry.replace(**new_entry, accession: number, locus: number, version:, last_updated:)

    filename = objs.first.file.filename

    ActiveRecord::Base.transaction do
      validation.objs.create!(
        _id:         'DDBJRecord',
        validity:    :valid,
        destination: objs.last.destination,

        file: {
          io:           StringIO.new(JSON.pretty_generate(current_record)),
          filename:     "#{filename.base}-#{Time.current.iso8601}.#{filename.extension}",
          content_type: objs.last.file.content_type
        }
      )

      @accession.update!(
        version:,
        last_updated_at: last_updated
      )
    end

    render :show
  end
end
