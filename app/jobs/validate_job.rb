class ValidateJob < ApplicationJob
  def perform(validation)
    validation.update! progress: :running, started_at: Time.current

    ActiveRecord::Base.transaction do
      validator = "Database::#{validation.db}::#{validation.via.camelize}Validator".constantize.new

      begin
        validator.validate validation
      rescue => e
        Rails.error.report e

        validation.objs.base.validity_error!

        validation.objs.base.validation_details.create!(
          severity: 'error',
          message:  e.message
        )
      else
        validation.objs.base.validity_valid! unless validation.objs.base.validity
      end

      raise ActiveRecord::Rollback if validation.reload.canceled?
    end
  ensure
    validation.update! progress: :finished, finished_at: Time.current unless validation.canceled?
  end
end
