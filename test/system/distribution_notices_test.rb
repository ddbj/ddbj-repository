require 'application_system_test_case'

# What the screen says and what its controls do. The endpoints' own
# rules are test/integration/admin/distribution_notices_test.rb; who is
# due, and what a run records, is
# test/services/distribution_notifier_test.rb.
class DistributionNoticesSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @project = projects(:primary)
    @project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.current + 5,
                     distribution_notified_at: nil, title: 'Soil metagenome survey')
  end

  # The bug this file exists for. `button_to` renders its own <form>, and
  # a nested form is dropped by the parser — so in a browser this button
  # belonged to the surrounding template form, and pressing it saved the
  # template and published the edit to every submitter. The endpoint was
  # never reached, so posting the route directly proved nothing.
  test 'sending yourself a test does not publish the edit' do
    visit admin_distribution_notices_path(tab: 'template')

    fill_in 'Subject', with: 'Draft that must not be published'

    assert_emails 1 do
      click_button 'Send a test to me'
    end

    assert_text 'Test notice sent to'
    assert_not_equal 'Draft that must not be published', DistributionNotifierTemplate.instance.subject
  end

  test 'saving the template does publish it' do
    visit admin_distribution_notices_path(tab: 'template')

    fill_in 'Subject', with: 'Published subject'
    click_button 'Save'

    assert_text 'Template saved.'
    assert_equal 'Published subject', DistributionNotifierTemplate.instance.subject
  end

  # `f.submit` renders its value AS the label, so naming the intent
  # relabelled the buttons to "save" and "test". Nothing failed; the
  # screen just started speaking in field values.
  test 'the buttons say what they do' do
    visit admin_distribution_notices_path(tab: 'template')

    assert_button 'Save'
    assert_button 'Send a test to me'
  end

  # The round trip the three tabs exist for: see what is about to go out,
  # send it, then find it in the history.
  test 'a notice sent from the queue turns up in the history' do
    visit admin_distribution_notices_path

    assert_text 'Soil metagenome survey'

    click_button 'Send all now'

    assert_text 'Sent 1 notice'
    assert_text 'No submitters are currently due'

    click_link 'Sent last 90 days'

    assert_text 'PRJDB000001'
    assert_text 'Delivered'
    assert_text 'Manual · bob'

    click_link 'Template'
    assert_text 'Preview'
  end

  # One mail per submitter, so two projects for the same person is one
  # thing to do, not two.
  test 'the due badge counts submitters rather than projects' do
    second = Submission.create!(db: :bioproject, source_id: 'PSUB-second', user: @project.submission.user)
    Project.create!(submission: second, project_type: :primary, status: :private,
                    accession: 'PRJDB900009', hold_date: Date.current + 5)

    visit admin_distribution_notices_path

    assert_selector 'a.nav-link.active .badge', text: '1'
  end

  # "It is automatic" is not reassuring on its own; "it ran this morning
  # and here is what it did" is.
  test 'the strip reports the result of the last scheduled run' do
    DistributionNotifier.call

    visit admin_distribution_notices_path

    assert_text 'Last run'
    assert_text '1 notice'
    assert_text '1 submitter'
    assert_link 'View the run in Jobs'
  end

  # The strip is about the schedule, so a curator's manual send in
  # between must not be mistaken for it having run.
  test 'a manual send is not reported as a run of the schedule' do
    visit admin_distribution_notices_path
    click_button 'Send all now'

    assert_text 'It has not run yet.'
  end

  # Without the skip in the history, the due list cannot explain why a
  # row is still sitting in it.
  test 'a skip appears in the history with its reason' do
    @project.submission.user.update!(email: nil)
    DistributionNotifier.call

    visit admin_distribution_notices_path(tab: 'sent')

    assert_text 'Skipped'
    assert_text 'no address'
  end

  test 'the history is searchable by accession and by submitter' do
    DistributionNotifier.call

    visit admin_distribution_notices_path(tab: 'sent')

    fill_in 'Search sent notices', with: 'PRJDB000001'
    click_button 'Search'
    assert_text @project.submission.user.uid

    fill_in 'Search sent notices', with: @project.submission.user.uid
    click_button 'Search'
    assert_text 'PRJDB000001'

    fill_in 'Search sent notices', with: 'PRJDB999999'
    click_button 'Search'
    assert_text 'No notices match this search.'
  end

  # Saving is publishing, so a body that would drop the accession list
  # is refused — next to the field that caused it, on the tab it was
  # edited on.
  test 'a body without the placeholder is refused on the tab it was edited on' do
    visit admin_distribution_notices_path(tab: 'template')

    fill_in 'Body', with: 'No placeholder here.'
    click_button 'Save'

    assert_text 'must contain the'
    assert_field 'Body', with: 'No placeholder here.'
  end

  test 'a blocked submitter is named at the top and links to their page' do
    stub_cloakman_lookup [], uids: [@project.submission.user.uid]

    @project.submission.user.update!(email: nil)
    DistributionNotifier.call

    visit admin_distribution_notices_path

    assert_text 'no address on file'

    click_link @project.submission.user.uid

    assert_current_path admin_user_path(uid: @project.submission.user.uid)
  end
end

class DistributionNoticesPreviewSystemTest < JavaScriptSystemTestCase
  setup do
    sign_in_as users(:bob)

    projects(:primary).update!(status: :private, accession: 'PRJDB000001',
                               hold_date: Date.current + 5, distribution_notified_at: nil)
  end

  # The preview used to render the saved template, so a curator checked
  # their draft against the text it was about to replace.
  test 'the preview follows the fields as they are typed' do
    visit admin_distribution_notices_path(tab: 'template')

    fill_in 'Subject', with: 'Live subject'
    fill_in 'Body',    with: "Opening line.\n\n%{accessions}\n\nClosing line."

    within '[data-test-preview]' do
      assert_text 'Live subject'
      assert_text 'Opening line.'
      assert_text 'Closing line.'

      # The accession block is server-rendered from a real candidate and
      # stays put while the prose around it changes.
      assert_text 'PRJDB000001'
    end
  end
end
