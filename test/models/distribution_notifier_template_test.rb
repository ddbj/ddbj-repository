require 'test_helper'

class DistributionNotifierTemplateTest < ActiveSupport::TestCase
  test 'instance falls back to the built-in defaults when none is saved' do
    template = DistributionNotifierTemplate.instance

    assert_not template.persisted?
    assert_equal DistributionNotifierTemplate::DEFAULT_SUBJECT, template.subject
    assert_includes template.body, DistributionNotifierTemplate::PLACEHOLDER
  end

  test 'render_body substitutes the accessions placeholder' do
    notice = DistributionNotifierTemplate::Notice.for(notified_project)
    body   = DistributionNotifierTemplate.instance.render_body([notice])

    assert_not_includes body, DistributionNotifierTemplate::PLACEHOLDER
    assert_match 'PRJDB000001', body
    assert_match '2030-01-15',  body
    assert_match notice.url,    body
  end

  test 'body_around_placeholder splits the prose the list goes between' do
    template       = DistributionNotifierTemplate.new(subject: 'x', body: "before\n\n#{DistributionNotifierTemplate::PLACEHOLDER}\n\nafter")
    before, after  = template.body_around_placeholder

    assert_equal 'before', before
    assert_equal 'after',  after
  end

  test 'Notice links to the submission on the web UI' do
    notice = DistributionNotifierTemplate::Notice.for(notified_project)

    assert_equal WebApp.url_for("/requests/#{notified_project.submission.request.id}"), notice.url
  end

  test 'a body without the accessions placeholder is invalid' do
    template = DistributionNotifierTemplate.new(subject: 'x', body: 'no placeholder here')

    assert_not template.valid?
    assert_includes template.errors[:body].join, DistributionNotifierTemplate::PLACEHOLDER
  end

  private

  def notified_project
    @notified_project ||= projects(:primary).tap {
      it.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.new(2030, 1, 15))
    }
  end
end
