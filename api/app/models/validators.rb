class Validators
  def self.validate(validation)
    ActiveRecord::Base.transaction do
      validation.processing!

      db        = DB.find { _1[:id] == validation.db }
      validator = db.fetch(:validator).constantize.new

      Rails.error.handle do
        begin
          validator.validate validation
        rescue => e
          validation.objs.base.update! validity: 'error', validation_details: {error: e.message}

          raise
        else
          validation.objs.base.validity_valid! unless validation.objs.base.validity
        end
      end

      raise ActiveRecord::Rollback if validation.reload.canceled?
    ensure
      unless validation.canceled?
        validation.update! status: 'finished', finished_at: Time.current
      end
    end
  end
end
