require 'test_helper'

class ReviewerAccessTest < ActiveSupport::TestCase
  setup do
    @alice = users(:alice)
    @set   = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)

    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
  end

  test 'mints an unguessable token when the link is enabled' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)

    assert access.token.present?
    assert_operator access.token.length, :>=, 24
  end

  test 'rejects a past expires_at' do
    assert_raises ActiveRecord::RecordInvalid do
      ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.day.ago)
    end
  end

  # The URL and what it carries are two different things, and only one of
  # them is the reader's to replace: a member re-minting a link they have
  # lost control of must not also un-share a colleague's work.
  test 're-enabling mints a fresh token and leaves the accessions where they are' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    was = access.token

    ReviewerAccess.enable!(@set, created_by: users(:carol), expires_at: 1.month.from_now)

    assert_equal 1,     ReviewerAccess.count
    assert_not_equal was, access.reload.token
    assert_equal ['PRJDB000001'], access.shared_accessions.pluck(:accession)
  end

  test 'active scope excludes expired links' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.day.from_now)

    assert_includes ReviewerAccess.active, access

    access.update_column(:expires_at, 1.day.ago) # bypass the future check

    assert_not_includes ReviewerAccess.active, access
    assert access.reload.expired?
  end

  test 'what the link shows is the accessions named on it, resolved to their rows' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    assert_equal [projects(:primary)], access.shared_rows(access.shared_accessions.pluck(:accession))
  end

  # The rows are resolved through the set every time, so what a reviewer
  # sees follows the set even where nothing has remembered to tidy up.
  # `delete_all` is how a row gets left behind without the callback below
  # having run.
  test 'an accession whose submission is no longer in the set is not on the link' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    @set.inclusions.delete_all

    assert_empty access.shared_rows(access.shared_accessions.pluck(:accession))
    assert_equal ['PRJDB000001'], access.shared_accessions.pluck(:accession)
  end

  # ...and taking a submission out properly does tidy up, so putting it
  # back in does not quietly re-share what was on the link last time.
  test 'taking the submission out of the set takes its accessions off the link' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    @set.inclusions.sole.destroy!

    assert_empty access.shared_accessions.reload
  end

  # A submission's accessions come off the link when it leaves the set,
  # and only that submission's do. The sweep asks the question in SQL
  # rather than by comparing two lists in Ruby, and this is what says it
  # still asks the same question.
  test 'taking one submission out leaves another submission on the link alone' do
    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)

    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001',          added_by: @alice)
    access.shared_accessions.create!(accession: samples(:first).accession, added_by: @alice)

    @set.inclusions.find_by!(submission_request: submission_requests(:bioproject)).destroy!

    assert_equal [samples(:first).accession], access.shared_accessions.reload.pluck(:accession)
  end

  test 'revoking the link takes what was on it with it' do
    access = ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)

    assert_difference 'ReviewerAccessAccession.count', -1 do
      access.destroy!
    end
  end
end
