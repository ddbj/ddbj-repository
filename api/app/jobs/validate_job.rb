class ValidateJob < ApplicationJob
  def perform(validation)
    ActiveRecord::Base.transaction do
      validation.update! progress: :running, started_at: Time.current

      validator = "Database::#{validation.db}::Validator".constantize.new

      Rails.error.handle do
        begin
          validator.validate validation
        rescue => e
          validation.objs.base.validity_error!

          validation.objs.base.validation_details.create!(
            severity: 'error',
            message:  e.message
          )

          raise
        else
          validation.objs.base.validity_valid! unless validation.objs.base.validity
        end
      end

      raise ActiveRecord::Rollback if validation.reload.canceled?
    ensure
      unless validation.canceled?
        validation.update! progress: :finished, finished_at: Time.current
      end
    end
  end
end
