class Database::BioProject::Param
  def self.build(params)
    BioProjectSubmissionParam.new(params.permit(:umbrella))
  end
end
