class ValidateJob < ApplicationJob
  def perform(request)
    Validators.validate request
  end
end
