require 'test_helper'

class PublicXML::Bp::ExchangePackageRendererTest < ActiveSupport::TestCase
  # Stand-in for the AR Project row: the renderer only reads accession /
  # project_type / first_published_at / last_published_at off it.
  Row = Data.define(:accession, :project_type, :first_published_at, :last_published_at)

  RECORD = {
    'projects'    => [{'accession' => 'PRJDB502', 'title' => 'Exchange test'}],
    'submission' => {'submitters' => [{'first_name' => 'Ada', 'last_name' => 'Lovelace', 'organizations' => [{'name' => 'DDBJ'}]}]}
  }.freeze

  LAST_RUN  = Time.zone.local(2024, 6, 1)
  EXEC_DATE = Time.zone.local(2024, 6, 30)

  def render(first_published_at: nil, last_published_at: nil, accession: 'PRJDB502', last_run: LAST_RUN, exec_date: EXEC_DATE)
    row = Row.new(accession:, project_type: 'primary', first_published_at:, last_published_at:)

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

  test 'eAdded when first_published_at is within (last_run, exec_date]' do
    node = render(first_published_at: Time.zone.local(2024, 6, 15))

    assert_equal 'eAdded', node.at_xpath('./Processing/@action').value
  end

  test 'eUpdated when only last_published_at is within the window' do
    node = render(first_published_at: Time.zone.local(2020, 1, 1), last_published_at: Time.zone.local(2024, 6, 15))

    assert_equal 'eUpdated', node.at_xpath('./Processing/@action').value
  end

  test 'eAdded wins when both first_published_at and last_published_at fall in the window' do
    node = render(first_published_at: Time.zone.local(2024, 6, 10), last_published_at: Time.zone.local(2024, 6, 20))

    assert_equal 'eAdded', node.at_xpath('./Processing/@action').value
  end

  test 'eUnchanged when both dates predate last_run' do
    node = render(first_published_at: Time.zone.local(2020, 1, 1), last_published_at: Time.zone.local(2020, 2, 1))

    assert_equal 'eUnchanged', node.at_xpath('./Processing/@action').value
  end

  test 'eUnchanged on the first-ever run (last_run nil) regardless of dates' do
    node = render(first_published_at: Time.zone.local(2024, 6, 15), last_run: nil)

    assert_equal 'eUnchanged', node.at_xpath('./Processing/@action').value
  end

  # By date, a project published later on the day of the last run fell
  # between the two runs: after the last run's day, it was not; within this
  # run's window, it was not either.
  test 'the window is to the moment, not the day' do
    assert_equal 'eAdded',     render(first_published_at: LAST_RUN + 5.hours).at_xpath('./Processing/@action').value
    assert_equal 'eUnchanged', render(first_published_at: LAST_RUN - 1.minute).at_xpath('./Processing/@action').value
  end

  test 'still renders the inherited Project body' do
    node = render

    assert_equal 'PRJDB502', node.at_xpath('./Project/Project/ProjectID/ArchiveID/@accession').value
  end
end
