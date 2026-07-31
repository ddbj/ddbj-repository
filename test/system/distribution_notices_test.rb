require 'application_system_test_case'

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
