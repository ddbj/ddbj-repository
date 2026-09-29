require 'test_helper'

class DRA::ImporterTest < ActiveSupport::TestCase
  FIXTURE = Rails.root.join('test/fixtures/files/dra/DRA000072')
  KINDS   = DRA::StagingClient::KINDS

  def documents = FIXTURE.glob('*.xml').sort_by { KINDS.index(it.basename.to_s.split('.')[1]) }.map(&:read)

  def retitled(title) = documents.map { it.sub('Whole genome analysis of Streptococcus salivarius', title) }

  def version(saved_at, docs = documents)
    DRA::StagingClient::Version.new(saved_at: Time.zone.parse(saved_at), documents: docs, digest: Digest::MD5.hexdigest(docs.join))
  end

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
    assert_equal Time.zone.parse('2010-01-01 10:00'), submission.request.created_at, 'dated by the first send, not the import'
  end

  # D-way moves a submission along by its status, not by a new version.
  test 'running again writes nothing to the chain, and still brings the status along' do
    submission = import(row).submission

    result = import(row(status: 800, release_date: Date.new(2026, 9, 1)))

    assert_equal :skipped, result.outcome
    assert_equal 2, submission.updates.count
    assert_equal 'public', submission.dra_submission.reload.status
    assert_equal Time.zone.local(2026, 9, 1), submission.dra_submission.first_published_at
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
  # Nothing is stored for it either — the patches are written only once
  # every version has converted.
  test 'a version that does not convert imports nothing, and stores nothing' do
    broken = row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00', documents + ['<SAMPLE alias="x"><FOO/></SAMPLE>'])])

    assert_no_difference -> { ActiveStorage::Blob.count } do
      assert_raises(DRA::Converter::Unmapped) { import(broken) }
    end

    assert_not Submission.dra_db.where(source_id: 'DRA000072').exists?
  end

  # A version saved with a tag missing is no state the record can hold. It
  # is left out of the history, not the whole submission with it — unless
  # it is the latest, which is what the record would be.
  test 'an earlier version that is not XML is left out, and a latest one fails the import' do
    malformed = documents.map { it.sub('</TITLE>', '') }

    assert_error_reported Nokogiri::XML::SyntaxError do
      result = import(row(versions: [version('2009-12-01 10:00', malformed), version('2010-01-01 10:00'), version('2010-02-01 10:00', retitled('A later title'))]))

      assert_equal :created, result.outcome
      assert_equal [Time.zone.parse('2010-01-01 10:00'), Time.zone.parse('2010-02-01 10:00')], result.submission.updates.order(:id).pluck(:created_at)
    end

    Submission.dra_db.where(source_id: 'DRA000072').destroy_all

    assert_raises(Nokogiri::XML::SyntaxError) { import(row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00', malformed)])) }
    assert_not Submission.dra_db.where(source_id: 'DRA000072').exists?
  end

  # A version that changes nothing the record says is still read. Were it
  # not, every run would read it again — and once a curator had edited the
  # record, diff it against the edit and write the edit away.
  test 'a curator edit survives a run that has nothing new from D-way' do
    reformatted = documents.map { it.gsub('><', ">\n<") }
    submission  = import(row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00', reformatted)])).submission

    edited = submission.materialised_record.deep_dup.tap { it['projects'][0]['title'] = 'Fixed by a curator' }
    submission.append_update!(edited, actor: 'admin:bob', source: :manual)

    assert_equal :skipped, import(row(versions: [version('2010-01-01 10:00'), version('2010-02-01 10:00', reformatted)])).outcome
    assert_equal 'Fixed by a curator', submission.reload.materialised_record.dig('projects', 0, 'title')
  end

  # D-way is where DRA is edited until the repository takes it, so a
  # version saved there wins — and is dated after the edit it writes over,
  # not before it.
  test 'a version from D-way after a curator edit is written over it, dated after it' do
    submission = import(row).submission

    edited = submission.materialised_record.deep_dup.tap { it['projects'][0]['title'] = 'Fixed by a curator' }
    manual = submission.append_update!(edited, actor: 'admin:bob', source: :manual)

    import(row(versions: row.versions + [version('2010-03-01 10:00', retitled('Changed in D-way'))]))

    latest = submission.updates.order(:id).last

    assert_equal 'Changed in D-way', submission.reload.materialised_record.dig('projects', 0, 'title')
    assert_operator latest.created_at, :>=, manual.created_at
  end

  # An object deleted after the last send, or a version dated before the
  # one it follows, changes what stands without a later save.
  test 'a latest state that changed without a later save is taken again' do
    submission = import(row).submission

    changed = row.versions[0..-2] + [version('2010-02-01 10:00', retitled('Changed without a later save'))]
    result  = import(row(versions: changed))

    assert_equal :updated, result.outcome
    assert_equal 'Changed without a later save', submission.reload.materialised_record.dig('projects', 0, 'title')
    assert_equal :skipped, import(row(versions: changed)).outcome
  end

  test 'a status the import does not know is refused by name' do
    error = assert_raises(ArgumentError) { import(row(status: 450)) }

    assert_match 'unknown DRA status 450', error.message
  end
end
