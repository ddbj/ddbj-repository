require 'test_helper'

class SubmissionNoticeMailerTest < ActionMailer::TestCase
  def issued(submission, accessions, names: {})
    notice = SubmissionNotice.accession_issued!(submission, accessions, names:)

    SubmissionNoticeMailer.with(notice:, first: accessions.first, count: accessions.size).accession_issued
  end

  test 'accession_issued — goes to the submitter address' do
    assert_equal ['alice@example.com'], issued(submissions(:bioproject), ['PRJDB1']).to
  end

  test 'accession_issued — BP, single accession, subject + body lists the value' do
    mail = issued(submissions(:bioproject), ['PRJDB123456'])

    assert_match(/BioProject accession issued: PRJDB123456/, mail.subject)
    assert_includes mail.from, 'repo@ddbj.nig.ac.jp'
    assert_match 'PRJDB123456', mail.body.encoded
  end

  test 'accession_issued — BS, multiple accessions, subject indicates "+N more"' do
    accs = (1..5).map {|i| "SAMD0000000#{i}" }
    mail = issued(submissions(:biosample), accs)

    assert_match(/BioSample accessions issued: SAMD00000001 \(\+4 more\)/, mail.subject)

    # all five must appear in body
    accs.each {|a| assert_match a, mail.body.encoded }
  end

  # Nothing reads replies to this mail; the thread is where it is answered.
  test 'accession_issued — says what the notice says, and points at the thread to answer it' do
    submission = submissions(:bioproject)
    text       = issued(submission, ['PRJDB1']).text_part.body.to_s

    assert_includes text, submission.request.messages.system_role.sole.body
    assert_includes text, WebApp.url_for("/requests/#{submission.request.id}")
    assert_not_includes text, 'reply to this email'
  end

  # The names are the submitter's, and `simple_format` only sanitises.
  test 'accession_issued — the HTML part shows a name as written' do
    html = issued(submissions(:biosample), ['SAMD00000001'], names: {'SAMD00000001' => 'x <y> <a href="https://example.com">z</a>'}).html_part.body.to_s

    assert_includes html, 'x &lt;y&gt; &lt;a href='
    assert_not_includes html, '<a href="https://example.com">'
  end

  test 'published — says what was made public' do
    submission = submissions(:biosample)
    notice     = SubmissionNotice.published!(submission, %w[SAMD00000001 SAMD00000002])
    mail       = SubmissionNoticeMailer.with(notice:, first: 'SAMD00000001', count: 2).published

    assert_includes notice.body, '2 samples of your BioSample submission'

    assert_equal '[DDBJ Repository] BioSample made public: SAMD00000001 (+1 more)', mail.subject
    assert_includes mail.text_part.body.to_s, notice.body
  end

  test 'accession_issued — staging environment prepends [Staging] to subject' do
    Rails.stub(:env, ActiveSupport::StringInquirer.new('staging')) do
      assert_match(/\A\[Staging\] /, issued(submissions(:bioproject), ['PRJDB1']).subject)
    end
  end

  test 'accession_issued — dev environment prepends [Dev] to subject' do
    Rails.stub(:env, ActiveSupport::StringInquirer.new('dev')) do
      assert_match(/\A\[Dev\] /, issued(submissions(:bioproject), ['PRJDB1']).subject)
    end
  end

  # No address → no mail at all. A synthesised recipient would only turn
  # the missing address into a bounce.
  test 'accession_issued — sends nothing when the address is unknown' do
    submission = submissions(:bioproject)
    submission.user.update!(email: nil)

    mail = issued(submission, ['PRJDB1'])

    assert_empty mail.to.to_a

    assert_no_emails { mail.deliver_now }
  end
end
