require 'test_helper'

class DistributionNotifierTemplateTest < ActiveSupport::TestCase
  test 'instance falls back to the built-in defaults when none is saved' do
    template = DistributionNotifierTemplate.instance

    assert_not template.persisted?
    assert_equal DistributionNotifierTemplate::DEFAULT_SUBJECT, template.subject
    assert_includes template.body, DistributionNotifierTemplate::PLACEHOLDER
  end

  test 'render_body substitutes the accessions placeholder' do
    project = projects(:primary)
    project.update!(status: :private, accession: 'PRJDB000001', hold_date: Date.new(2030, 1, 15))

    body = DistributionNotifierTemplate.instance.render_body(projects: [project], web_url: 'http://example.com')

    assert_not_includes body, DistributionNotifierTemplate::PLACEHOLDER
    assert_match 'PRJDB000001', body
    assert_match '2030-01-15',  body
    assert_match "http://example.com/web/requests/#{project.submission.request.id}", body
  end

  test 'a body without the accessions placeholder is invalid' do
    template = DistributionNotifierTemplate.new(subject: 'x', body: 'no placeholder here')

    assert_not template.valid?
    assert_includes template.errors[:body].join, DistributionNotifierTemplate::PLACEHOLDER
  end
end
