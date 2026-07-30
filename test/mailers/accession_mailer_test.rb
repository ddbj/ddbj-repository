require 'test_helper'

class AccessionMailerTest < ActionMailer::TestCase
  test 'issued — goes to the submitter address' do
    mail = AccessionMailer.with(submission: submissions(:bioproject), accessions: ['PRJDB1']).issued

    assert_equal ['alice@example.com'], mail.to
  end

  test 'issued — BP, single accession, subject + body lists the value' do
    submission = submissions(:bioproject)
    mail = AccessionMailer.with(submission:, accessions: ['PRJDB123456']).issued

    assert_match(/BioProject accession issued: PRJDB123456/, mail.subject)
    assert_includes mail.from, 'repo@ddbj.nig.ac.jp'
    assert_match 'PRJDB123456', mail.body.encoded
  end

  test 'issued — BS, multiple accessions, subject indicates "+N more"' do
    submission = submissions(:biosample)
    accs       = (1..5).map {|i| "SAMD0000000#{i}" }
    mail = AccessionMailer.with(submission:, accessions: accs).issued

    assert_match(/BioSample accessions issued: SAMD00000001 \(\+4 more\)/, mail.subject)

    # all five must appear in body
    accs.each {|a| assert_match a, mail.body.encoded }
  end

  test 'issued — staging environment prepends [Staging] to subject' do
    submission = submissions(:bioproject)
    Rails.stub(:env, ActiveSupport::StringInquirer.new('staging')) do
      mail = AccessionMailer.with(submission:, accessions: ['PRJDB1']).issued
      assert_match(/\A\[Staging\] /, mail.subject)
    end
  end

  test 'issued — dev environment prepends [Dev] to subject' do
    submission = submissions(:bioproject)
    Rails.stub(:env, ActiveSupport::StringInquirer.new('dev')) do
      mail = AccessionMailer.with(submission:, accessions: ['PRJDB1']).issued
      assert_match(/\A\[Dev\] /, mail.subject)
    end
  end

  # No address → no mail at all. A synthesised recipient would only turn
  # the missing address into a bounce.
  test 'issued — sends nothing when the address is unknown' do
    submission = submissions(:bioproject)
    submission.user.update!(email: nil)

    mail = AccessionMailer.with(submission:, accessions: ['PRJDB1']).issued

    assert_empty mail.to.to_a

    assert_no_emails { mail.deliver_now }
  end
end
