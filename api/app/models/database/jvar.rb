module Database::JVar
  class Validator
    def validate(validation)
      validation.objs.without_base.each &:validity_valid!
    end
  end

  class Submitter
    def submit(submission)
      # do nothing
    end
  end
end
