module Database::BioSample
  class Validator
    include DDBJValidator
  end

  class Submitter
    def submit(submission)
      # do nothing
    end
  end
end
