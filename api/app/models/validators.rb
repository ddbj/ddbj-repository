class Validators
  def self.validate(request, &on_finish)
    ActiveRecord::Base.transaction do
      request.processing!

      db        = DB.find { _1[:id] == request.db }
      validator = db.fetch(:validator).constantize.new

      Rails.error.handle do
        begin
          validator.validate request
        rescue => e
          request.objs.base.update! validity: 'error', validation_details: {error: e.message}

          raise
        else
          request.objs.base.validity_valid! unless request.objs.base.validity
        end
      end

      raise ActiveRecord::Rollback if request.reload.canceled?
    ensure
      unless request.canceled?
        request.finished!

        on_finish&.call
      end
    end
  end
end
