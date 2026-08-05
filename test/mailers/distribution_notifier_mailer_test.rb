require 'test_helper'

class DistributionNotifierMailerTest < ActionMailer::TestCase
  setup do
    @project = projects(:primary)
    @project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.new(2030, 1, 15))

    @mail = DistributionNotifierMailer.with(user: @project.submission.user, projects: [@project]).release_notice
    @url  = WebApp.url_for("/requests/#{@project.submission.request.id}")
  end

  test 'release_notice lists each accession and its hold date' do
    assert_equal '[DDBJ Repository] Your data will be released soon', @mail.subject
    assert @mail.to.present?

    body = @mail.body.encoded

    assert_match 'PRJDB000001', body
    assert_match '2030-01-15',  body
  end

  test 'the text part spells the submission URL out' do
    assert_match @url, @mail.text_part.body.decoded
  end

  # A bare URL isn't reliably clickable, and the submitter has to reach the
  # submission to message a curator about the release date.
  test 'the html part links to the submission' do
    assert_match %r{<a href="#{Regexp.escape(@url)}">}, @mail.html_part.body.decoded
  end
end
