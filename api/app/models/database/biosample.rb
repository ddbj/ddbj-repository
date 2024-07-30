module Database::BioSample
  class Param
    def self.build(params)
      nil
    end
  end

  class Validator
    include DDBJValidator
  end

  class Submitter
    def submit(submission)
      # do nothing
    end
  end
end
