class ValidateJob < ApplicationJob
  retry_on Errno::ECONNREFUSED, Net::ReadTimeout, wait: :polynomially_longer

  after_discard do |job, error|
    Rails.error.report error

    validation = job.arguments.first

    next if validation.canceled?

    ActiveRecord::Base.transaction do
      validation.objs.base.validity_error!

      validation.objs.base.validation_details.create!(
        severity: "error",
        message:  error.message
      )
    end
  end

  def perform(validation)
    validation.update! progress: :running, started_at: Time.current

    begin
      ActiveRecord::Base.transaction do
        validator = "Database::#{validation.db}::Validator".constantize.new

        validator.validate validation
        validation.objs.base.validity_valid! unless validation.objs.base.validity

        raise ActiveRecord::Rollback if validation.reload.canceled?
      end
    ensure
      validation.update! progress: :finished, finished_at: Time.current unless validation.canceled?
    end
  end
end
