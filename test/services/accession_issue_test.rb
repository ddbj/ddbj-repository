require 'test_helper'

class AccessionIssueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup do
    Sequence.ensure_records!
  end

  # --- BP ---

  test 'BP: allocates PRJDB, stamps Project, transitions status, patches the record' do
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

    # Since ddbj-canon/v2 the accession is ordinary record content, so
    # issuance appends a chain entry and the record agrees with the column
    # instead of silently lagging behind it. The append also nils the cache
    # stamp (SubmissionUpdate#after_create), so no separate invalidation.
    submission.reload
    assert_nil submission.cached_at_update_id
    assert_equal 2, submission.updates.count
    assert_equal result.accessions.first, submission.materialised_record.dig('project', 'accession')
  end

  # The chain entry and the event describe the same action; linking them
  # keeps the activity feed to one line.
  test 'BP: the recorded event points at the patch it produced' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.append_update!({'project' => {'title' => 'seed'}}, actor: 'test-seed')

    AccessionIssue.call(submission:, actor: 'admin:tanaka')

    event = CurationEvent.last

    assert_equal submission.updates.order(:id).last.id, event.submission_update_id
    assert_equal 'issued 1 PRJDB accession (PRJDB1)', event.summary
  end

  # A submission that has never been applied has no record to patch. The
  # typed column still carries the accession; the next import reconciles.
  test 'BP: issues without a chain when there is no record yet' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    result = AccessionIssue.call(submission:, actor: 'test-curator')

    assert_equal 1, result.accessions.size
    assert_equal 0, submission.updates.count
    assert_nil      CurationEvent.last.submission_update_id
  end

  # `materialised_record` can be served from the cache while the chain
  # behind it is unreplayable — the importers create exactly that state
  # (safe_prior_materialised swallows the failure, then re-primes). The
  # read then succeeds and the append raises.
  test 'BP: reports a broken chain behind a warm cache, without stamping' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.append_update!({'project' => {'title' => 'seed'}}, actor: 'test-seed')

    poisoned = SubmissionUpdate.create_with_patch!(
      submission:, patch_json: 'not-json', db: 'bioproject', status: :applied,
      actor: 'test', source: :manual, patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    # A cache that claims to be current even though the replay cannot run.
    submission.prime_cache!(bytes: Oj.dump({'project' => {'title' => 'seed'}}, mode: :strict),
                            update_id: poisoned.id)

    assert_raises(AccessionIssue::ChainBroken) { AccessionIssue.call(submission:, actor: 'test') }
    assert_nil projects(:primary).reload.accession, 'the raise must roll the allocation back'
  end

  # Stamping an accession into a record that cannot be replayed would
  # record something the chain can never show. Not a refusal: nothing
  # about this submission is ineligible, it is broken — and the two reach
  # the curator as different words and different colours.
  test 'BP: raises ChainBroken when the patch chain is unreadable' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    SubmissionUpdate.create_with_patch!(
      submission:, patch_json: 'not-json', db: 'bioproject', status: :applied,
      actor: 'test', source: :manual, patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    error = assert_raises(AccessionIssue::ChainBroken) { AccessionIssue.call(submission:, actor: 'test') }

    assert_match(/patch chain is unreadable/, error.message)
    assert_nil projects(:primary).reload.accession, 'a failed issuance must not stamp the column'
    assert_not_kind_of AccessionIssue::Refused, error, 'a broken chain must not read as a refusal'
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

    result = nil

    assert_enqueued_emails 1 do
      result = AccessionIssue.call(submission:, actor: 'test')
    end

    assert_equal 'sent', result.mail_status
  end

  # The two ways a notification goes nowhere without anything going
  # wrong. Both used to be indistinguishable from a delivery: nothing
  # raised, so `mail_error` was nil, and every screen read that as sent.
  test 'a submitter with no address on file is recorded as such, not as mailed' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.user.update!(email: nil)

    result = nil

    assert_no_enqueued_emails do
      result = AccessionIssue.call(submission:, actor: 'test')
    end

    assert_equal 'no_address', result.mail_status
    assert_equal 1, result.accessions.size, 'the accessions are the outcome either way'
  end

  # While the environment restricts outgoing mail, an address outside it
  # is suppressed by the interceptor — after the mailer has been queued,
  # where nothing that reports on the issuance can see it. Asked here
  # instead, of the object that does the restricting.
  test 'a recipient outside the mail allowlist is recorded as restricted' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.user.update!(email: 'someone@example.com')

    result = nil

    restrict_mail_to 'ddbj.nig.ac.jp' do
      assert_no_enqueued_emails do
        result = AccessionIssue.call(submission:, actor: 'test')
      end
    end

    assert_equal 'restricted', result.mail_status
  end

  test 'a recipient inside the allowlist is mailed as normal' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')
    submission.user.update!(email: 'curator@ddbj.nig.ac.jp')

    result = nil

    restrict_mail_to 'ddbj.nig.ac.jp' do
      assert_enqueued_emails 1 do
        result = AccessionIssue.call(submission:, actor: 'test')
      end
    end

    assert_equal 'sent', result.mail_status
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

  # Samples are keyed on `alias` (== sample_name) in the record, so the
  # patch has to land the right accession on the right entry.
  test 'BS: writes each accession onto the matching record entry' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    submission.append_update!(
      {'samples' => [{'alias' => 'fixture-sample-1'}, {'alias' => 'fixture-sample-2'}]},
      actor: 'test-seed'
    )

    AccessionIssue.call(submission:, actor: 'test-curator')

    by_alias = submission.reload.materialised_record.fetch('samples').index_by { it['alias'] }

    assert_equal samples(:first).reload.accession,  by_alias.fetch('fixture-sample-1')['accession']
    assert_equal samples(:second).reload.accession, by_alias.fetch('fixture-sample-2')['accession']
  end

  # A sample the record does not carry is skipped rather than invented —
  # the DB row and the record can legitimately disagree mid-migration.
  test 'BS: leaves the record alone for samples it does not carry' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    submission.append_update!({'samples' => [{'alias' => 'fixture-sample-1'}]}, actor: 'test-seed')

    AccessionIssue.call(submission:, actor: 'test-curator')

    entries = submission.reload.materialised_record.fetch('samples')

    assert_equal 1, entries.size
    assert_equal samples(:first).reload.accession, entries.first['accession']
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

    # Use a fresh instance of AccessionIssue and stub the record write to
    # raise — that triggers the Rails transaction rollback path without
    # mocha-style any_instance plumbing.
    service = AccessionIssue.new(submission:, actor: 'test')
    service.define_singleton_method(:stamp_record!) {|&_| raise 'simulated post-update failure' }

    assert_raises(RuntimeError) { service.call }

    project.reload
    assert_nil project.accession, 'rollback must clear accession'
    assert_equal 'curating', project.status, 'rollback must keep prior status'

    assert_equal before_next, Sequence.find_by(scope: 'bp').next,
                 'sequence stays at the warmed value because the failed allocate! is rolled back'
  end

  # --- issuable? / issuable ---

  # The admin UI gates its buttons on these, so they must agree with what
  # `call` actually accepts.
  test 'issuable? mirrors the refusal rules' do
    project = projects(:primary)

    project.update!(accession: nil, status: 'curating')
    assert AccessionIssue.issuable?(project)

    project.update!(status: 'submission_accepted')
    assert AccessionIssue.issuable?(project)

    project.update!(status: 'public')
    assert_not AccessionIssue.issuable?(project), 'status outside ISSUABLE_FROM is not issuable'

    project.update!(accession: 'PRJDB000001', status: 'curating')
    assert_not AccessionIssue.issuable?(project), 'an already-accessioned row is not issuable'
  end

  test 'issuable narrows a relation to the rows call would stamp' do
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'public')

    issuable = AccessionIssue.issuable(submissions(:biosample).samples)

    assert_includes issuable, samples(:first)
    assert_not_includes issuable, samples(:second)
  end

  # --- ST26 ---

  test 'refuses st26 submissions (no Project or Sample to stamp)' do
    assert_raises AccessionIssue::Refused do
      AccessionIssue.call(submission: submissions(:st26), actor: 'test')
    end
  end
end
