require 'test_helper'

class DistributionNotifierMailerTest < ActionMailer::TestCase
  test 'release_notice lists each accession, its hold date, and a submission link' do
    project = projects(:primary)
    project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.new(2030, 1, 15))

    mail = DistributionNotifierMailer.with(user: project.submission.user, projects: [project]).release_notice

    assert_equal '[DDBJ Repository] Your data will be released soon', mail.subject
    assert mail.to.present?

    body = mail.body.encoded
    assert_match 'PRJDB000001', body
    assert_match '2030-01-15',  body
    assert_match "/web/requests/#{project.submission.request.id}", body
  end
end
