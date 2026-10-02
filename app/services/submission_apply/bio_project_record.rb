# A BioProject record: its project becomes the submission's Project row.
# One project, as a BioProject XML carries (ddbj-validator refuses more,
# BP_R0037).
class SubmissionApply::BioProjectRecord < SubmissionApply::V3Record
  private

  def build_rows(submission, tree)
    project = tree['projects'].first

    Project.create!(submission:, project_type: project['project_type'] == 'umbrella' ? :umbrella : :primary)

    submission.sync_projections!(tree)
  end
end
