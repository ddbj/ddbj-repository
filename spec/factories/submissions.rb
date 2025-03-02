FactoryBot.define do
  factory :submission do
    validation { association(:validation, :valid) }
    visibility { :public }

    param {
      if validation.db == "BioProject"
        association(:bioproject_submission_param)
      else
        nil
      end
    }
  end
end
