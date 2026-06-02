require 'test_helper'

class Phase1SchemaSmokeTest < ActiveSupport::TestCase
  # End-to-end smoke: build Submission -> Project -> ProjectLink ->
  # Sample -> SampleReference in one transaction, reload, and verify destroy
  # cascades reach project_links and sample_references.
  test 'create and destroy a Submission graph' do
    parent_sub  = Submission.create!(db: :bioproject, user: users(:alice))
    parent_proj = parent_sub.create_project!(project_type: :umbrella)

    child_sub  = Submission.create!(db: :bioproject, user: users(:alice))
    child_proj = child_sub.create_project!(project_type: :primary, accession: 'PRJDB099999')

    ProjectLink.create!(child_project: child_proj, parent_project: parent_proj)
    ProjectLink.create!(child_project: child_proj, external_accession: 'PRJNA707598')

    sample_sub = Submission.create!(db: :biosample, user: users(:alice))
    sample     = sample_sub.samples.create!(sample_name: 'smoke-1', package_group: 'Standard')

    SampleReference.create!(sample:, ref_db: 'bioproject', ref_accession: 'PRJDB099999')
    SampleReference.create!(sample:, ref_db: 'sra',        ref_accession: 'DRS000001')

    # Reload chain and verify associations
    reloaded_child = Submission.find(child_sub.id).project

    assert_includes reloaded_child.parents, parent_proj
    assert_equal 2, reloaded_child.parent_links.count
    assert reloaded_child.parent_links.exists?(external_accession: 'PRJNA707598')
    # parent project sees the child via children
    assert_includes parent_proj.reload.children, child_proj

    assert_equal 2, sample.sample_references.count
    assert sample.sample_references.exists?(ref_db: 'bioproject')

    # destroy cascade: deleting submission removes project + project_links
    assert_difference -> { Project.count } => -1, -> { ProjectLink.count } => -2 do
      child_sub.destroy!
    end

    # destroy cascade: deleting submission removes sample + sample_references
    assert_difference -> { Sample.count } => -1, -> { SampleReference.count } => -2 do
      sample_sub.destroy!
    end
  end
end
