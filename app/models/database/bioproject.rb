module Database::BioProject
  def self.build_param(params)
    BioProjectSubmissionParam.new(params.permit(:umbrella))
  end
end
