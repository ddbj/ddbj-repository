class ValidateJob < ApplicationJob
  def perform(validation)
    validation.update! progress: :running

    ActiveRecord::Base.transaction do
      validator = "Database::#{validation.db}::#{validation.via.camelize}Validator".constantize.new

      begin
        validator.validate validation
      rescue => e
        Rails.error.report e

        validation.objs.base.validation_details.create!(
          severity: 'error',
          message:  e.message
        )
      end

      raise ActiveRecord::Rollback if validation.reload.canceled?
    end
  ensure
    validation.update! progress: :finished, finished_at: Time.current unless validation.canceled?
  end
end
