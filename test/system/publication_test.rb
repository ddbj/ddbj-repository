require 'application_system_test_case'

# When an object was first made public and when what is public about it
# last changed (DB-2096) are what the exchange XML, the public XML and the
# livelists date it by. They move with the status a curator sets here —
# into public and out of it — and with nothing else a curator does.
class PublicationSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @req     = submission_requests(:bioproject)
    @project = projects(:primary)
  end

  def set_status(label)
    visit admin_submission_request_path(@req)

    within '[data-test-curator-edit]' do
      select label, from: 'curation[status]'
      click_button 'Save changes'
    end

    assert_equal 200, page.status_code
  end

  test 'making a project public dates it, and taking it out of public dates its last change' do
    published = Time.zone.local(2026, 10, 1, 10)

    travel_to(published) { set_status 'Public' }

    assert_equal [published, published], @project.reload.values_at(:first_published_at, :last_published_at)

    suppressed = Time.zone.local(2026, 11, 1, 10)

    travel_to(suppressed) { set_status 'Temporarily suppressed' }

    assert_equal [published, suppressed], @project.reload.values_at(:first_published_at, :last_published_at)

    travel_to(Time.zone.local(2026, 12, 1, 10)) { set_status 'Public' }

    assert_equal published, @project.reload.first_published_at, 'first published once, however often again'
  end

  # A status that stays where it was is no publication.
  test 'saving a project that is already public moves neither' do
    @project.update_columns(status: Lifecycleable::STATUSES.fetch('public'), first_published_at: 1.year.ago, last_published_at: 1.month.ago)
    before = @project.reload.values_at(:first_published_at, :last_published_at)

    set_status 'Public'

    assert_equal before, @project.reload.values_at(:first_published_at, :last_published_at)
  end

  test 'the Samples tab dates the samples it makes public, and only those' do
    req = submission_requests(:biosample)
    one, other = samples(:first), samples(:second)

    visit samples_admin_submission_request_path(req)

    check "Select #{one.sample_name}"
    select 'Public', from: 'bulk_row[status]'
    click_button 'Apply'

    assert_text 'Bulk-updated 1'
    assert one.reload.first_published_at
    assert_nil other.reload.first_published_at
  end

  test 'the ledger dates a project taken out of public' do
    @project.update_columns(status: Lifecycleable::STATUSES.fetch('public'), first_published_at: 1.year.ago, last_published_at: 1.year.ago)

    visit admin_submission_requests_path

    check "Select ##{@req.id}"
    select 'Temporarily suppressed', from: 'bulk[status]'
    click_button 'Apply'

    assert_text 'Set 1 project to temporarily suppressed'
    assert_in_delta Time.current, @project.reload.last_published_at, 1.minute
  end
end
