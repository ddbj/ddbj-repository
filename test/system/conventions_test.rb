require 'application_system_test_case'

# The cross-cutting rules in CLAUDE.md, held to on the screens that carry
# them. Each of these was decided once and is easy to decide differently
# by accident on the next screen — which is the whole reason they are
# written down.
class EmptyStateSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  # A filter that matches nothing has to say which filter, or the reader
  # is left to work out whether the data or the query is at fault.
  test 'a filtered list reads its filters back and offers a way out' do
    visit admin_submission_requests_path(db: %w[bioproject], status: %w[curating])

    within '[data-test-empty-state="filtered"]' do
      assert_text 'No requests match these filters'
      assert_text 'Database: Bioproject'
      assert_text 'Curation: Curating'
      assert_link 'Clear filters'
    end

    click_link 'Clear filters'

    assert_no_selector '[data-test-empty-state]'
  end

  # A button that clears more than it says is worst here, where the
  # reader has just been told nothing matched and has no way to notice
  # the rest of their query going with it.
  test 'clearing a search keeps the other things narrowing the list' do
    stub_cloakman_search 'nobody', []
    stub_cloakman_lookup [cloakman_profile(:bob), cloakman_profile(:dave)], uids: %w[bob dave]

    visit admin_users_path(q: 'nobody', segment: 'staff')

    within '[data-test-empty-state="filtered"]' do
      assert_text 'Within Staff.'

      click_link 'Clear the search'
    end

    assert_equal 'staff', Rack::Utils.parse_query(URI.parse(current_url).query.to_s)['segment']
  end

  test 'a list narrowed by search and filters together says so on the button' do
    visit admin_submission_requests_path(q: 'nothing-matches-this', db: %w[bioproject])

    within '[data-test-empty-state="filtered"]' do
      assert_text 'Searching for "nothing-matches-this"'
      assert_text 'Database: Bioproject'
      assert_link 'Clear search and filters'
    end
  end

  test 'a search that matches nothing offers to clear the search' do
    stub_cloakman_search 'nobody-by-that-name', []

    visit admin_users_path(q: 'nobody-by-that-name')

    within '[data-test-empty-state="filtered"]' do
      assert_text 'No accounts match this search.'
      assert_link 'Clear the search'
    end
  end

  # Nothing has ever been here, so the useful thing is what will appear
  # and how to start it — not a restatement of "0".
  test 'a list that has never had anything says what will appear' do
    visit admin_migration_runs_path

    within '[data-test-empty-state="first_run"]' do
      assert_text 'No migration runs yet.'
      assert_text 'Runs appear here once a database has been imported'
    end
  end

  # A queue reaching zero is the point of the queue. Saying it as an
  # achievement, with nothing to press: a button here would send somebody
  # looking for work the screen has just said there is none of.
  test 'an empty queue reads as an outcome and offers nothing to press' do
    visit admin_my_queue_path

    assert_selector '[data-test-empty-state="clear"]', minimum: 1

    within '[data-test-section="unclaimed"]' do
      assert_text      'Nothing here.'
      assert_no_button 'Clear'
      assert_no_link   'Clear'
    end
  end
end

class PageRangeSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  # Carrying the page back across a bulk action is what lets a curator
  # resume where they were — and it is also how they land on a page that
  # no longer exists, once their own changes emptied it. Pagy neither
  # raises nor clamps: it returns an empty page, so the header counts
  # rows the body says are not there.
  test 'a page past the end lands on the last one that exists' do
    visit admin_submission_requests_path(page: 99)

    assert_equal '1', Rack::Utils.parse_query(URI.parse(current_url).query.to_s)['page']
    assert_no_selector '[data-test-empty-state]'
  end

  test 'the same holds for the samples table, which paginates separately' do
    request = submission_requests(:biosample)

    visit samples_admin_submission_request_path(request, samples_page: 99)

    assert_equal '1', Rack::Utils.parse_query(URI.parse(current_url).query.to_s)['samples_page']
  end
end

class RelativeTimeSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  # Rounding to "4d" is what makes a queue readable, and it is also what
  # makes "which Tuesday?" unanswerable — so the exact value does not
  # leave, it just stops taking up room.
  test 'a relative time carries the absolute one in the markup and on hover' do
    request = submission_requests(:st26)

    visit admin_submission_requests_path

    within "tr:has(a[href='#{admin_submission_request_path(request)}'])" do
      element = find('time')

      assert_equal request.updated_at.iso8601, element['datetime']
      assert_equal request.updated_at.strftime('%Y-%m-%d %H:%M'), element['title']
    end
  end
end

class FilterRetentionSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  # A filtered view has to survive being acted on: working through a
  # queue means pressing Apply and carrying on where you were, and
  # rebuilding the filter every time is the same as not having one.
  test 'a bulk action returns to the same filtered page' do
    submission = submissions(:st26)

    visit admin_submission_requests_path(db: %w[st26], q: '', page: 1)

    check "Select ##{submission.request.id}"
    select 'Curating', from: 'bulk[status]'
    click_button 'Apply'

    query = Rack::Utils.parse_query(URI.parse(current_url).query.to_s)

    assert_equal %w[st26], Array(query['db[]'])
    assert_equal '1',      query['page']
  end
end
