require 'test_helper'

# The unified curation rail: status, assignee, hold date and the internal
# comment save as one form. Replaces the four separate endpoints
# (projects / hold_dates / curator_comments / bulk_update_samples-for-all).
class AdminCurationsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @project    = projects(:primary)
    @req    = @submission.request
  end

  # --- curation rows (status / assignee) --------------------------------

  # Status lands on the curation rows, assignee on the request — one save,
  # two destinations.
  test 'PATCH update sets the status on the BP Project and the assignee on the request' do
    patch admin_submission_curation_path(@submission),
          params: {curation: {status: 'curating', assignee_id: users(:bob).id}}

    assert_redirected_to admin_submission_request_path(@req)
    assert_equal 'curating',  @project.reload.status
    assert_equal users(:bob), @req.reload.assignee
  end

  test 'PATCH update with the unassigned sentinel clears the assignee' do
    @req.assign!(users(:bob))

    patch admin_submission_curation_path(@submission),
          params: {curation: {assignee_id: CurationUpdate::UNASSIGNED}}

    assert_redirected_to admin_submission_request_path(@req)
    assert_nil @req.reload.assignee
  end

  test 'PATCH update leaves a blank field alone' do
    @req.assign!(users(:bob))

    patch admin_submission_curation_path(@submission),
          params: {curation: {status: '', assignee_id: ''}}

    assert_equal 'private',   @project.reload.status
    assert_equal users(:bob), @req.reload.assignee
  end

  test 'PATCH update rejects a non-admin assignee' do
    patch admin_submission_curation_path(@submission),
          params: {curation: {status: 'curating', assignee_id: users(:alice).id}}

    assert_redirected_to admin_submission_request_path(@submission.request)
    assert_match(/must be an admin user/, flash[:alert])
    assert_equal 'private', @project.reload.status, 'a refused save must not mutate status either'
  end

  test 'PATCH update rejects an unknown status' do
    patch admin_submission_curation_path(@submission),
          params: {curation: {status: 'no_such_status'}}

    assert_redirected_to admin_submission_request_path(@submission.request)
    assert_match(/Unknown status/, flash[:alert])
    assert_equal 'private', @project.reload.status
  end

  test 'PATCH update applies to every sample of a BS submission' do
    submission = submissions(:biosample)

    patch admin_submission_curation_path(submission),
          params: {curation: {status: 'curating', assignee_id: users(:bob).id}}

    assert_equal ['curating'],  submission.samples.distinct.pluck(:status)
    assert_equal users(:bob),   submission.request.reload.assignee
  end

  # A save that only touched the comment must not rewrite every sample row.
  test 'PATCH update skips the row write when the posted values already match' do
    @project.update!(status: 'curating')
    @req.assign!(users(:bob))
    before = @project.reload.updated_at

    travel 1.second do
      patch admin_submission_curation_path(@submission),
            params: {curation: {status: 'curating', assignee_id: users(:bob).id, curator_comment: 'note'}}
    end

    assert_equal before, @project.reload.updated_at
    assert_equal 'note',      @submission.reload.curator_comment
  end

  # --- the audit trail ---------------------------------------------------
  # The two histories divide on "does this reach the DDBJ Record": record
  # content becomes a patch, everything else becomes a CurationEvent. A
  # save must land in exactly one of them.

  test 'a status + assignee save records an event, not a patch' do
    assert_no_difference '@submission.updates.count' do
      assert_difference 'CurationEvent.count', 1 do
        patch admin_submission_curation_path(@submission),
              params: {curation: {status: 'curating', assignee_id: users(:bob).id}}
      end
    end

    event = CurationEvent.last

    assert_equal 'curation_updated',   event.action
    assert_equal 'admin:bob',          event.actor
    assert_equal 1,                    event.row_count
    assert_equal 'set 1 project to curating and assigned the request to bob', event.summary
  end

  # hold_date IS record content, so the chain already tells that story —
  # recording it twice would make the two histories disagree.
  test 'a hold-date save records a patch, not an event' do
    seed_chain

    assert_no_difference 'CurationEvent.count' do
      assert_difference '@submission.updates.count', 1 do
        patch admin_submission_curation_path(@submission),
              params: {curation: {hold_date: '2026-12-31'}}
      end
    end
  end

  test 'a save that changes nothing records nothing' do
    @project.update!(status: 'curating')
    @req.assign!(users(:bob))

    assert_no_difference 'CurationEvent.count' do
      patch admin_submission_curation_path(@submission),
            params: {curation: {status: 'curating', assignee_id: users(:bob).id}}
    end
  end

  test 'a comment-only save is still recorded' do
    assert_difference 'CurationEvent.count', 1 do
      patch admin_submission_curation_path(@submission),
            params: {curation: {curator_comment: 'internal note'}}
    end

    assert_equal 'updated the curator comment', CurationEvent.last.summary
  end

  test 'Assign to me is recorded like any other assignee change' do
    assert_difference 'CurationEvent.count', 1 do
      post admin_submission_request_assignment_path(@req)
    end

    assert_equal 'assigned the request to bob', CurationEvent.last.summary
  end

  # --- curator comment ---------------------------------------------------

  test 'PATCH update writes the curator comment without touching the chain' do
    assert_no_difference '@submission.updates.count' do
      patch admin_submission_curation_path(@submission),
            params: {curation: {curator_comment: "first note\nsecond note"}}
    end

    assert_equal "first note\nsecond note", @submission.reload.curator_comment
  end

  test 'PATCH update with an empty comment nulls the column' do
    @submission.update_columns(curator_comment: 'existing')

    patch admin_submission_curation_path(@submission),
          params: {curation: {curator_comment: ''}}

    assert_nil @submission.reload.curator_comment
  end

  # --- hold date ---------------------------------------------------------

  test 'PATCH update sets hold_date, appends a patch and projects the column' do
    seed_chain

    assert_difference '@submission.updates.count', 1 do
      patch admin_submission_curation_path(@submission),
            params: {curation: {hold_date: '2026-12-31'}}
    end

    assert_equal '2026-12-31',           @submission.reload.materialised_record.dig('submission', 'hold_date')
    assert_equal Date.new(2026, 12, 31), @project.reload.hold_date
  end

  test 'PATCH update with a blank hold date drops the key and clears the column' do
    seed_chain(hold_date: '2026-12-31')
    @project.update!(hold_date: Date.new(2026, 12, 31))

    patch admin_submission_curation_path(@submission),
          params: {curation: {hold_date: ''}}

    refute @submission.reload.materialised_record['submission'].key?('hold_date'),
           'blank input must drop the key, not store an empty string'
    assert_nil @project.reload.hold_date
  end

  # The rail hides the field outside BioProject because nothing there acts
  # on it. A template is not a guard: a replayed POST would otherwise
  # append a real patch setting a date nothing will ever honour.
  test 'PATCH update refuses a hold date on a non-BioProject submission' do
    submission = submissions(:biosample)
    submission.append_update!({'schema_version' => 'v3'}, actor: 'test-seed', source: :manual)

    assert_no_difference 'submission.updates.count' do
      patch admin_submission_curation_path(submission),
            params: {curation: {hold_date: '2026-12-31'}}
    end

    assert_match(/BioProject submissions only/, flash[:alert])
  end

  test 'PATCH update rejects month-name / non-ISO hold dates strictly' do
    seed_chain

    ['May', '12', '2026/12/31', '2026-13-01', '2026-02-30', 'today'].each do |bad|
      patch admin_submission_curation_path(@submission), params: {curation: {hold_date: bad}}

      assert_match(/valid YYYY-MM-DD/, flash[:alert], "expected reject for #{bad.inspect}")
      assert_nil @submission.reload.materialised_record.dig('submission', 'hold_date'),
                 "must not fabricate a hold date from #{bad.inspect}"
    end
  end

  test 'an unchanged hold date generates no patch' do
    seed_chain(hold_date: '2026-12-31')

    assert_no_difference '@submission.updates.count' do
      patch admin_submission_curation_path(@submission), params: {curation: {hold_date: '2026-12-31'}}
    end
  end


  # --- rendering / auth --------------------------------------------------

  # `submission.hold_date` is a v3 field for any DB, but only BioProject
  # projects it onto a column, syncs it, or notifies on it. Offering the
  # field elsewhere would report "saved" for something nothing honours.
  # The comment is a typed column, independent of the chain, so it stays
  # editable when the record cannot be replayed — but the hold-date input
  # must disappear rather than offer to overwrite a value it cannot show.
  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)

    patch admin_submission_curation_path(@submission), params: {curation: {status: 'curating'}}

    assert_response :forbidden
  end

  # --- participation ------------------------------------------------------
  # Working on a request puts you in it. Nothing about who owns it moves,
  # which is what makes it safe to do without asking.

  test 'saving the curation rail makes the curator a participant' do
    patch admin_submission_curation_path(@submission), params: {curation: {status: 'curating'}}

    assert_equal [users(:bob)], @req.reload.participants
    assert_nil   @req.assignee, 'participation must not claim the request'
  end

  test 'replying to the submitter makes the curator a participant' do
    post admin_submission_request_messages_path(@req),
         params: {submission_message: {body: 'a question'}}

    assert_equal [users(:bob)], @req.reload.participants
  end

  test 'a save that changed nothing does not make anyone a participant' do
    patch admin_submission_curation_path(@submission), params: {curation: {status: ''}}

    assert_empty @req.reload.participants
  end

  # Claiming is the other axis: it says who owns this, and saying so is
  # not the same as having worked on it. It is also not a claim to have
  # READ anything — an assignee reaches their queue through the
  # assignment itself, and subscribing them here would discharge the very
  # question that prompted the claim.
  test 'Assign to me does not add a participant' do
    post admin_submission_request_assignment_path(@req)

    assert_equal users(:bob), @req.reload.assignee
    assert_empty @req.participants
  end

  # --- assign to me ------------------------------------------------------

  test 'POST assignment claims the request for the current curator' do
    post admin_submission_request_assignment_path(@req)

    assert_redirected_to admin_submission_request_path(@req)
    assert_equal users(:bob), @req.reload.assignee
  end

  # The queue's whole point: an unapplied request is claimable, which the
  # old submission-scoped endpoint could not express at all.
  test 'POST assignment claims a request that has not been applied' do
    request = SubmissionRequest.new(user: users(:alice), db: 'bioproject')
    attach_ddbj_record(request)
    request.save!

    post admin_submission_request_assignment_path(request)

    assert_redirected_to admin_submission_request_path(request)
    assert_equal users(:bob), request.reload.assignee
  end

  private

  def seed_chain(hold_date: nil)
    record = {'schema_version' => 'v3', 'submission' => {'submitters' => [{'first_name' => 'Hanako'}]}}
    record['submission']['hold_date'] = hold_date if hold_date

    @submission.append_update!(record, actor: 'test-seed', source: :manual)
  end
end
