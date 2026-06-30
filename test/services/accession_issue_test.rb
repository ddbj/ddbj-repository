require 'test_helper'

class AccessionIssueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    Sequence.ensure_records!
  end

  # --- BP ---

  test 'BP: allocates PRJDB, stamps Project, transitions status, invalidates materialised cache' do
    submission = submissions(:bioproject)
    project    = projects(:primary).tap {|p| p.update!(accession: nil, status: 'curating') }

    # Warm the cache with a real SubmissionUpdate so the FK on
    # cached_at_update_id holds.
    submission.append_update!({'project' => {'title' => 'seed'}}, actor: 'test-seed')
    submission.materialised_record # write-through cache populates
    assert submission.reload.cached_materialised_record.attached?,
           'cache blob must be attached after write-through'

    result = AccessionIssue.call(submission:, actor: 'test-curator')

    assert_equal 1, result.accessions.size
    assert_match(/\APRJDB\d+\z/, result.accessions.first)

    project.reload
    assert_equal result.accessions.first, project.accession
    assert_equal 'accession_issued',      project.status

    # `/**/accession` is volatile so no SubmissionUpdate is created — see
    # AccessionIssue#invalidate_cache! rationale. Cache stamp MUST be
    # nulled so the next read picks up the typed-column accession. The
    # blob itself stays attached until displaced by the next prime_cache!
    # (orphan turnover is bounded by re-import / read cadence).
    submission.reload
    assert_nil submission.cached_at_update_id
  end

  test 'BP: refuses when project already has accession' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    assert_raises AccessionIssue::Refused do
      AccessionIssue.call(submission:, actor: 'test')
    end
  end

  test 'BP: refuses when project status is not issuable (e.g. public)' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'public')

    assert_raises(AccessionIssue::Refused) {
      AccessionIssue.call(submission:, actor: 'test')
    }
  end

  test 'BP: enqueues an AccessionMailer delivery on success' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    assert_enqueued_emails 1 do
      AccessionIssue.call(submission:, actor: 'test')
    end
  end

  # --- BS ---

  test 'BS: allocates SAMD for all un-accessioned issuable samples' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    result = AccessionIssue.call(submission:, actor: 'test-curator')

    assert_equal 2, result.accessions.size
    assert(result.accessions.all? {|a| a.match?(/\ASAMD\d{8,}\z/) })

    [samples(:first), samples(:second)].each do |s|
      s.reload
      assert_includes result.accessions, s.accession
      assert_equal 'accession_issued', s.status
    end
  end

  test 'BS: skips samples that are already accessioned or in non-issuable status' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: 'SAMD00000999', status: 'accession_issued')

    result = AccessionIssue.call(submission:, actor: 'test')

    assert_equal 1, result.accessions.size
    assert_equal result.accessions.first, samples(:first).reload.accession
    assert_equal 'SAMD00000999',           samples(:second).reload.accession, 'already-issued sample untouched'
  end

  test 'BS: refuses when no sample is eligible' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'public')
    samples(:second).update!(accession: 'SAMD00000999', status: 'public')

    assert_raises AccessionIssue::Refused do
      AccessionIssue.call(submission:, actor: 'test')
    end
  end

  test 'BS: enqueues exactly one mail regardless of how many samples were stamped' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    assert_enqueued_emails 1 do
      AccessionIssue.call(submission:, actor: 'test')
    end
  end

  # --- Transaction safety ---

  test 'BP: rolls back Sequence + Project on validation failure inside the transaction' do
    submission = submissions(:bioproject)
    project    = projects(:primary)
    project.update!(accession: nil, status: 'curating')

    Sequence.allocate!(:bp, 1) # warm
    before_next = Sequence.find_by(scope: 'bp').next

    # Use a fresh instance of AccessionIssue and stub `invalidate_cache!`
    # to raise — that triggers the Rails transaction rollback path
    # without mocha-style any_instance plumbing.
    service = AccessionIssue.new(submission:, actor: 'test')
    service.define_singleton_method(:invalidate_cache!) {|_| raise 'simulated post-update failure' }

    assert_raises(RuntimeError) { service.call }

    project.reload
    assert_nil project.accession, 'rollback must clear accession'
    assert_equal 'curating', project.status, 'rollback must keep prior status'

    assert_equal before_next, Sequence.find_by(scope: 'bp').next,
                 'sequence stays at the warmed value because the failed allocate! is rolled back'
  end

  # --- ST26 ---

  test 'refuses st26 submissions (no Project or Sample to stamp)' do
    assert_raises AccessionIssue::Refused do
      AccessionIssue.call(submission: submissions(:st26), actor: 'test')
    end
  end
end
