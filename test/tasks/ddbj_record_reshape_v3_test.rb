require 'test_helper'
require 'rake'

class DDBJRecordReshapeV3TaskTest < ActiveSupport::TestCase
  XML = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB000604.xml').read.freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('ddbj_record:reshape_v3')
    Rake::Task['ddbj_record:reshape_v3'].reenable
  end

  def import
    BioProject::Importer.new(
      psub_id:          'PSUB000604',
      xml:              XML,
      user_uid:         'migration-test',
      project_type:     'primary',
      accession:        'PRJDB502',
      migration_run_id: SecureRandom.uuid
    ).call
  end

  # A BioProject imported and then edited before the spec's shape changed:
  # its chain holds `project` under ddbj-canon/v2, and its checksum is of the
  # converter's old output.
  def stored_before_the_change
    submission = import.submission
    converted  = BioProject::Converter.new(xml: XML, project_row: {project_type: 'primary', accession: 'PRJDB502'}).call
    old        = DDBJRecord::ReshapeV3.old_shape(submission.materialised_record)

    old['project']['title'] = 'Curator title'

    submission.update_columns(canonical_version: DDBJRecord::Canonicalizer::NUMBER - 1)
    submission.append_update!(old, actor: 'admin:tanaka')
    submission.update_columns(
      canonical_version: DDBJRecord::Canonicalizer::NUMBER - 1,
      source_checksum:   Submission.source_checksum_of(DDBJRecord::ReshapeV3.old_shape(converted))
    )

    submission.reload
  end

  test 'rewrites a stored record into the current shape and keeps the edits made here' do
    submission = stored_before_the_change

    assert_output(/rewritten: /) { Rake::Task['ddbj_record:reshape_v3'].invoke }

    record = submission.reload.materialised_record

    assert_not record.key?('project')
    assert_equal 'Curator title', record.dig('projects', 0, 'title')
    assert_kind_of String, record.dig('projects', 0, 'organism', 'taxonomy_id')
    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.canonical_version
  end

  # The import after the rewrite converts a source that did not change: it
  # has to be recognised by the checksum taken before, or it is diffed
  # against the record and the edit is reverted.
  test 'the next import of an unchanged source keeps the edits and takes the new checksum' do
    submission = stored_before_the_change

    assert_output(/rewritten: /) { Rake::Task['ddbj_record:reshape_v3'].invoke }

    assert_equal :skipped, import.outcome
    assert_equal 'Curator title', submission.reload.materialised_record.dig('projects', 0, 'title')

    converted = BioProject::Converter.new(xml: XML, project_row: {project_type: 'primary', accession: 'PRJDB502'}).call
    assert_equal Submission.source_checksum_of(converted), submission.source_checksum
  end

  test 'leaves a record already in the current shape alone' do
    submission = import.submission

    assert_no_difference -> { submission.updates.count } do
      assert_output(/unchanged: /) { Rake::Task['ddbj_record:reshape_v3'].invoke }
    end
  end
end
