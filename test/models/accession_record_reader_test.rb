require 'test_helper'

# Reading one accessioned row out of a record: which subtree comes back,
# and — when none does — which of the reasons it is. Told apart because
# telling one as another sends somebody looking in the wrong place.
class AccessionRecordReaderTest < ActiveSupport::TestCase
  def slice_for(submission, row) = AccessionRecordReader.new(submission).slice(row)

  test 'a BioProject reads its project' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'Deep sea survey'}}, actor: 'test')

    assert_equal 'Deep sea survey', slice_for(submission, projects(:primary)).subtree['title']
  end

  test 'a BioSample reads the one sample, by alias' do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!(
      {
        'samples' => [
          {'alias' => 'somebody else', 'title' => 'Not it'},
          {'alias' => sample.sample_name, 'title' => 'This one'}
        ]
      },
      actor: 'test'
    )

    assert_equal 'This one', slice_for(submission, sample).subtree['title']
  end

  # The property the streaming exists for. Measured 2026-09-04 at 4,000
  # samples: the streamed read is 108ms holding nothing where building
  # the record is 55ms holding 20MB — about twice the wall time for flat
  # memory, in a worker that also runs the jobs.
  #
  # Asserted by refusing to let the whole record be built. A value alone
  # would come back either way.
  test 'a cached BioSample record is streamed rather than built' do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!({'samples' => [{'alias' => sample.sample_name, 'title' => 'Streamed'}]}, actor: 'test')
    submission.materialised_record # primes the cache the stream reads

    submission.reload.stub(:materialised_record, -> { flunk 'built the whole record to read one row of it' }) do |primed|
      assert_equal 'Streamed', AccessionRecordReader.new(primed).slice(sample).subtree['title']
    end
  end

  # Invalidation clears the stamp and leaves the blob attached, so a
  # streamed read that trusts the attachment serves the pre-edit record.
  test 'a stale cache is not read' do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!({'samples' => [{'alias' => sample.sample_name, 'title' => 'BEFORE'}]}, actor: 'test')
    submission.materialised_record
    submission.append_update!({'samples' => [{'alias' => sample.sample_name, 'title' => 'AFTER'}]}, actor: 'test')

    assert submission.reload.cached_materialised_record.attached?
    assert_nil submission.cached_at_update_id

    assert_equal 'AFTER', slice_for(submission, sample).subtree['title']
  end

  test 'an ST.26 entry is read out of the record the apply wrote, by id' do
    submission = submissions(:st26)
    attach_submission_files submission

    entry = submission.entries.first

    assert_equal entry.entry_id, slice_for(submission, entry).subtree['id']
  end

  # Each way there can be no subtree says which way it was. A reader
  # asked twice must not be told the first answer's reason.
  test 'the reasons are told apart, and do not carry over between calls' do
    submission = submissions(:biosample)
    sample     = samples(:first)
    reader     = AccessionRecordReader.new(submission)

    assert_equal AccessionRecordReader::RECORD_ABSENT, reader.slice(sample).unavailable_reason

    submission.append_update!({'samples' => [{'alias' => 'somebody else', 'title' => 'Not it'}]}, actor: 'test')

    assert_equal AccessionRecordReader::RECORD_MISSING_ROW, reader.slice(sample).unavailable_reason
  end

  test 'a chain that cannot be replayed says so rather than raising' do
    submission = submissions(:biosample)

    SubmissionUpdate.create_with_patch!(
      submission:              submission,
      patch_json:              'not-json-at-all',
      db:                      'biosample',
      status:                  'applied',
      actor:                   'test',
      patch_canonical_version: 1
    )

    assert_equal AccessionRecordReader::RECORD_UNREADABLE, slice_for(submission, samples(:first)).unavailable_reason
  end

  # An ST.26 attachment IS the record: there is nothing behind it to
  # replay, so a gone object is said rather than raised at a submitter.
  test 'an ST.26 record whose file has gone is said, not raised' do
    submission = submissions(:st26)
    attach_submission_files submission

    ActiveStorage::Blob.service.delete(submission.ddbj_record.blob.key)

    assert_equal AccessionRecordReader::RECORD_LOST, slice_for(submission, submission.entries.first).unavailable_reason
  end
end
