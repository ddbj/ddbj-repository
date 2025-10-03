class RenewAccessionJob < ApplicationJob
  def perform(renewal)
    renewal.update! progress: :running, started_at: Time.current

    ActiveRecord::Base.transaction do
      begin
        JSON.parse renewal.file.download
      rescue JSON::ParserError => e
        renewal.validation_details.create!(
          severity: 'error',
          message:  e.message
        )
      end

      if renewal.validation_details.empty?
        renewal.validity_valid!
      else
        renewal.validity_invalid!
      end
    end
  ensure
    renewal.update! progress: :finished, finished_at: Time.current unless renewal.canceled?
  end
end
