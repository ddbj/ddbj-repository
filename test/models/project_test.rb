require 'test_helper'

class ProjectTest < ActiveSupport::TestCase
  test 'status enum mapping uses status_ prefix and 5100..5900 codes' do
    project = projects(:primary)

    assert_equal 'private', project.status
    assert       project.status_private?
    assert_equal 5400,      Project.statuses['private']
    assert_equal 5900,      Project.statuses['temporarily_suppressed']
  end

  test 'accession format requires PRJD[B-Z]\d+' do
    project = Project.new(submission: submissions(:bioproject), project_type: :primary)

    project.accession = 'PRJDB42365'
    assert project.valid?

    project.accession = 'PRJNA707598'
    assert_not project.valid?
    assert_includes project.errors[:accession], 'is invalid'

    project.accession = nil
    assert project.valid?
  end

  test 'assignee_must_be_admin rejects non-admin users' do
    project = projects(:primary)

    project.assignee = users(:alice)
    assert_not project.valid?
    assert_includes project.errors[:assignee], 'must be an admin user'

    project.assignee = users(:bob)
    assert project.valid?

    project.assignee = nil
    assert project.valid?
  end

  test 'parent / children relations through ProjectLink' do
    parent = projects(:umbrella)
    child  = projects(:primary)

    assert_equal parent, child.parent
    assert_includes parent.children, child
  end
end
