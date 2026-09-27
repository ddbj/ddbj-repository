require 'test_helper'

class DRA::ImporterTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/fixtures/files/dra/DRA000072')
  KINDS   = DRA::StagingClient::KINDS

  def documents = FIXTURE.glob('*.xml').sort_by { KINDS.index(it.basename.to_s.split('.')[1]) }.map(&:read)

  def retitled(title) = documents.map { it.sub('Whole genome analysis of Streptococcus salivarius', title) }

  def version(saved_at, docs = documents) = DRA::StagingClient::Version.new(saved_at: Time.zone.parse(saved_at), documents: docs)

  def row(**overrides)
    DRA::StagingClient::Submission.new(
      sub_id:       72,
      submitter_id: 'dra-submitter',
      status:       700,
      accession:    'DRA000072',
      hold_date:    Date.new(2027, 1, 1),
      dist_date:    nil,
      release_date: nil,
      versions:     [version('2010-01-01 10:00'), version('2010-02-01 10:00', retitled('A later title'))],
      **overrides
    )
  end

  def import(row) = DRA::Importer.new(row, migration_run_id: SecureRandom.uuid).call

  test 'every version becomes a patch dated when it was saved, and the record is the last' do
    result     = import(row)
    submission = result.submission

    assert_equal :created, result.outcome
    assert submission.dra_db?
    assert_equal 'DRA000072', submission.source_id
    assert_equal 'dra-submitter', submission.user.uid

    assert_equal [Time.zone.parse('2010-01-01 10:00'), Time.zone.parse('2010-02-01 10:00')],
                 submission.updates.order(:id).pluck(:created_at)

    assert_equal 'A later title', submission.materialised_record.dig('projects', 0, 'title')

    assert_equal({'accession' => 'DRA000072', 'status' => 'private', 'hold_date' => Date.new(2027, 1, 1)},
                 submission.dra_submission.attributes.slice('accession', 'status', 'hold_date'))

    assert_equal 'applied', submission.request.status
    assert submission.request.migration_origin?
  end

  # D-way moves a submission along by its status, not by a new version.
  test 'running again writes nothing to the chain, and still brings the status along' do
    submission = import(row).submission

    result = import(row(status: 800, release_date: Date.new(2026, 9, 1)))

    assert_equal :skipped, result.outcome
    assert_equal 2, submission.updates.count
    assert_equal 'public', submission.dra_submission.reload.status
    assert_equal Date.new(2026, 9, 1), submission.dra_submission.release_date
  end

  test 'a version saved since the last run is appended' do
    submission = import(row).submission

    later  = row.versions + [version('2010-03-01 10:00', retitled('The latest title'))]
    result = import(row(versions: later))

    assert_equal :updated, result.outcome
    assert_equal 3, submission.updates.count
    assert_equal 'The latest title', submission.reload.materialised_record.dig('projects', 0, 'title')
  end

  test 'a version that says what the last one said adds no patch' do
    submission = import(row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00')])).submission

    assert_equal 1, submission.updates.count
  end

  test 'a submission never sent, or without its DRA accession, is not imported' do
    assert_equal :no_versions,  import(row(versions: [])).outcome
    assert_equal :no_accession, import(row(accession: nil)).outcome
    assert_not Submission.dra_db.where(source_id: 'DRA000072').exists?
  end

  test 'a submission that belongs to someone else is not re-attributed' do
    import(row)

    assert_raises(DRA::Importer::CrossUserError) { import(row(submitter_id: 'someone-else')) }
  end

  # A document the converter refuses stops the submission rather than
  # importing the versions before it: a history with a hole is not one.
  test 'a version that does not convert imports nothing' do
    broken = row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00', documents + ['<SAMPLE alias="x"><FOO/></SAMPLE>'])])

    assert_raises(DRA::Converter::Unmapped) { import(broken) }
    assert_not Submission.dra_db.where(source_id: 'DRA000072').exists?
  end
end
