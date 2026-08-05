require 'test_helper'

class PublicXML::Bp::ExchangePackageRendererTest < ActiveSupport::TestCase
  # Stand-in for the AR Project row: the renderer only reads accession /
  # release_date / dist_date off it.
  Row = Data.define(:accession, :release_date, :dist_date)

  RECORD = {
    'project'    => {'accession' => 'PRJDB502', 'title' => 'Exchange test'},
    'submission' => {'submitters' => [{'first_name' => 'Ada', 'last_name' => 'Lovelace', 'organizations' => [{'name' => 'DDBJ'}]}]}
  }.freeze

  LAST_RUN  = Time.zone.local(2024, 6, 1)
  EXEC_DATE = Time.zone.local(2024, 6, 30)

  def render(release_date: nil, dist_date: nil, accession: 'PRJDB502', last_run: LAST_RUN, exec_date: EXEC_DATE)
    row = Row.new(accession:, release_date:, dist_date:)

    PublicXML::Bp::ExchangePackageRenderer.new(record: RECORD, row:, last_run:, exec_date:).call
  end

  test 'inserts <Processing owner=DDBJ id=counter> between Project and Submission' do
    node = render

    assert_equal %w[Project Processing Submission], node.element_children.map(&:name),
                 'Processing must sit between Project and Submission'

    processing = node.at_xpath('./Processing')
    assert_equal 'DDBJ', processing['owner']
    assert_equal '502',  processing['id'], 'id is the numeric counter of the accession'
  end

  test 'eAdded when release_date is within (last_run, exec_date]' do
    node = render(release_date: Date.new(2024, 6, 15))

    assert_equal 'eAdded', node.at_xpath('./Processing/@action').value
  end

  test 'eUpdated when only dist_date is within the window' do
    node = render(release_date: Date.new(2020, 1, 1), dist_date: Date.new(2024, 6, 15))

    assert_equal 'eUpdated', node.at_xpath('./Processing/@action').value
  end

  test 'eAdded wins when both release_date and dist_date fall in the window' do
    node = render(release_date: Date.new(2024, 6, 10), dist_date: Date.new(2024, 6, 20))

    assert_equal 'eAdded', node.at_xpath('./Processing/@action').value
  end

  test 'eUnchanged when both dates predate last_run' do
    node = render(release_date: Date.new(2020, 1, 1), dist_date: Date.new(2020, 2, 1))

    assert_equal 'eUnchanged', node.at_xpath('./Processing/@action').value
  end

  test 'eUnchanged on the first-ever run (last_run nil) regardless of dates' do
    node = render(release_date: Date.new(2024, 6, 15), last_run: nil)

    assert_equal 'eUnchanged', node.at_xpath('./Processing/@action').value
  end

  test 'still renders the inherited Project body' do
    node = render

    assert_equal 'PRJDB502', node.at_xpath('./Project/Project/ProjectID/ArchiveID/@accession').value
  end
end
