require 'test_helper'

class ProjectLinkTest < ActiveSupport::TestCase
  test 'valid with parent_project only' do
    link = project_links(:internal)

    assert link.valid?
    assert_nil link.external_accession
  end

  test 'valid with external_accession only' do
    link = project_links(:external)

    assert link.valid?
    assert_nil link.parent_project
  end

  test 'rejects when both parent_project and external_accession are present' do
    link = ProjectLink.new(
      child_project:      projects(:primary),
      parent_project:     projects(:umbrella),
      external_accession: 'PRJNA999999'
    )

    assert_not link.valid?
    assert_includes link.errors[:base], 'specify exactly one of parent_project or external_accession'
  end

  test 'rejects when neither parent_project nor external_accession is set' do
    link = ProjectLink.new(child_project: projects(:primary))

    assert_not link.valid?
    assert_includes link.errors[:base], 'specify exactly one of parent_project or external_accession'
  end

  test 'database CHECK constraint blocks bypassing model validation' do
    assert_raises ActiveRecord::StatementInvalid do
      ProjectLink.connection.execute(
        "INSERT INTO project_links (child_project_id, parent_project_id, external_accession, created_at, updated_at) " \
        "VALUES (#{projects(:primary).id}, #{projects(:umbrella).id}, 'PRJNA1', NOW(), NOW())"
      )
    end
  end
end
