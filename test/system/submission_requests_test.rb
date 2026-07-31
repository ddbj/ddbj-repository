require 'application_system_test_case'

class SubmissionRequestsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @req    = @submission.request

    @submission.update_columns(source_id: 'PSUB000604')
  end

  # A bulk action posts from a form whose URL carries the current filter,
  # and the redirect is rebuilt from those params — a set that had drifted
  # from what the ledger actually has, so searching and then acting threw
  # the search away. Only visible by doing it in that order.
  test 'a bulk action keeps the search it was started from' do
    projects(:primary).update!(status: 'submission_accepted')

    visit admin_submission_requests_path
    fill_in 'Search requests', with: 'PSUB000604'
    click_button 'Search'

    assert_text "##{@req.id}"

    check "Select ##{@req.id}"
    select 'Curating', from: 'bulk[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated'
    assert_field 'Search requests', with: 'PSUB000604'
    assert_equal 'curating', projects(:primary).reload.status
  end

  # Both buttons live in one form, because a nested form would be dropped.
  # That form is a POST carrying no `_method`, so the second button's
  # `formaction` reaches a POST-only route — an earlier PATCH form made
  # Rack::MethodOverride rewrite every submit, and this button 404'd.
  test 'issuing accessions from the ledger reaches the issuance route' do
    projects(:primary).update!(accession: nil, status: 'curating')

    visit admin_submission_requests_path

    check "Select ##{@req.id}"
    click_button 'Issue accessions'

    assert_text 'Issued'
    assert_not_nil projects(:primary).reload.accession
  end

  # Search leads and the facets fold away — but a filter that is on must
  # never be invisible, so the panel opens itself when one is.
  test 'the facet panel opens itself when a facet is already on' do
    visit admin_submission_requests_path

    assert_selector '[data-bs-target="#more-filters"][aria-expanded="false"]'
    assert_no_selector '#more-filters.show'

    visit admin_submission_requests_path(db: %w[bioproject])

    assert_selector '[data-bs-target="#more-filters"][aria-expanded="true"]'
    assert_selector '#more-filters.show'
  end
end

class MyQueueSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @req = submission_requests(:bioproject)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting on this')
  end

  test 'claiming an unclaimed request moves it into the curator own section' do
    visit admin_root_path

    within '.list-group' do
      assert_text "##{@req.id}"
      click_button 'Assign to me'
    end

    assert_text "Assigned to #{users(:bob).uid}"
    assert_equal users(:bob), @req.reload.assignee
  end

  test 'a queue row leads to the thread it is about' do
    visit admin_root_path

    click_link 'Reply'

    assert_current_path messages_admin_submission_request_path(@req)
    assert_text 'still waiting on this'
  end
end
