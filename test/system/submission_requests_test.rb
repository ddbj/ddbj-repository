require 'application_system_test_case'

class SubmissionRequestsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @req        = @submission.request

    # `update_columns`: Submission validates its uploaded record on save,
    # and the fixture has none. Giving it one would say nothing about the
    # ledger search this test is here for.
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
  # never be invisible, so the panel announces itself as open when one is.
  # Asserted through `aria-expanded`, which is the state assistive tech
  # reads, rather than through whichever class Bootstrap toggles.
  # The Samples screen carries the same two-buttons-one-form shape, and
  # the same trap: a PATCH form would make Rack::MethodOverride rewrite
  # the issuance button's POST into a PATCH the route does not accept.
  test 'issuing accessions from the samples screen reaches the issuance route' do
    submission = submissions(:biosample)
    submission.samples.update_all(accession: nil, status: Lifecycleable::STATUSES.fetch('curating'))

    visit samples_admin_submission_request_path(submission.request)

    # The scope radio is what the bulk bar acts on; "selected" with
    # nothing ticked is refused, which is its own correct behaviour.
    choose 'All 2 matching the filter'
    click_button 'Issue SAMD'

    assert_text 'Issued'
    assert_empty submission.samples.where(accession: nil)
  end

  test 'the facet panel opens itself when a facet is already on' do
    visit admin_submission_requests_path

    assert_selector 'button[aria-expanded="false"]', text: 'More filters'

    visit admin_submission_requests_path(db: %w[bioproject])

    assert_selector 'button[aria-expanded="true"]', text: 'More filters'
  end
end

# What the queue screen says. Which requests belong in which section is
# MyQueue's rule and is tested at test/services/my_queue_test.rb.
class MyQueueSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @req = submission_requests(:bioproject)
    @req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting on this')
  end

  test 'each section carries the rule that put a request in it' do
    visit admin_root_path

    assert_text 'Assigned to me'
    assert_text 'assignment only changes when someone changes it'

    assert_text "I'm involved"
    assert_text 'You replied or edited here'

    assert_text 'Unclaimed'
    assert_text 'every curator sees this section identically'
  end

  test 'the row says why it is here and offers the one thing to do about it' do
    visit admin_root_path

    within '[data-test-section="unclaimed"]' do
      assert_text '1 unread message'
      assert_link 'Reply'
      assert_no_button 'Issue'
    end
  end

  test 'an empty queue says so rather than showing three empty boxes' do
    @req.messages.destroy_all

    visit admin_root_path

    assert_text 'Nothing is waiting on a curator right now.'
  end

  # The sections are the design, so the claim under test is where the row
  # ends up — not merely that a column changed.
  test 'claiming an unclaimed request moves it into the curator own section' do
    visit admin_root_path

    within '[data-test-section="unclaimed"]' do
      assert_text "##{@req.id}"
      click_button 'Assign to me'
    end

    assert_text "Assigned to #{users(:bob).uid}"

    visit admin_root_path

    within('[data-test-section="assigned"]')  { assert_text "##{@req.id}" }
    within('[data-test-section="unclaimed"]') { assert_no_text "##{@req.id}" }
  end

  # Replying is the other half of the model: it keeps the request in your
  # queue without taking it away from whoever owns it.
  test 'a request someone else owns that I replied on shows as involved' do
    @req.assign!(users(:dave))
    @req.participate!(users(:bob))

    visit admin_root_path

    within('[data-test-section="involved"]') do
      assert_text "##{@req.id}"
      assert_text 'assignee dave'
    end
  end

  test 'a queue row leads to the thread it is about' do
    visit admin_root_path

    click_link 'Reply'

    assert_current_path messages_admin_submission_request_path(@req)
    assert_text 'still waiting on this'
  end
end
