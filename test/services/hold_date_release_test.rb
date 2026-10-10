require 'test_helper'

class HoldDateReleaseTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @today = Date.current

    DwayTakeover.record!(by: 'test')
  end

  def dra_with(relations, row: dra_submissions(:dra), status: :private, hold_date: @today)
    row.update!(status:, hold_date:)

    row.submission.append_update!({
      'schema_version' => 'v3',
      'submission'     => {'alias' => 'sub1', 'accession' => row.accession},
      'experiments'    => [{'alias' => 'exp', 'accession' => 'DRX000001'}],
      'projects'       => [{'alias' => 'own-project', 'accession' => projects(:primary).accession}],
      'relations'      => relations
    }, actor: 'test')

    row
  end

  def part_of(target)
    {
      'type'   => 'part_of',
      'source' => {'type' => 'experiment', 'accession' => 'DRX000001'},
      'target' => target
    }
  end

  def another_dra
    submission = Submission.create!(db: 'dra', user: users(:alice))

    DRASubmission.create!(submission:, accession: 'DRA000002', status: :private)
  end

  test 'releases a BioProject on its hold date, and tells its submitter' do
    project = projects(:primary)
    project.update!(hold_date: @today)

    assert_equal 1, HoldDateRelease.call(today: @today).projects

    assert project.reload.status_public?
    assert project.submission.request.messages.system_role.exists?
  end

  test 'releases one temporarily suppressed on its hold date, as D-way did' do
    project = projects(:primary)
    project.update!(status: :temporarily_suppressed, hold_date: @today)

    HoldDateRelease.call(today: @today)

    assert project.reload.status_public?
  end

  # The date is Tokyo's and the timestamps are kept in UTC: published early
  # on its hold date, Tokyo time, it has been public since.
  test 'a hold date is a day in Tokyo' do
    project = projects(:primary)
    project.update!(status: :temporarily_suppressed, hold_date: @today, last_published_at: @today.in_time_zone('Asia/Tokyo') + 5.hours)

    HoldDateRelease.call(today: @today)

    assert project.reload.status_temporarily_suppressed?

    project.update!(last_published_at: @today.in_time_zone('Asia/Tokyo') - 1.minute)

    HoldDateRelease.call(today: @today)

    assert project.reload.status_public?
  end

  # Nobody pressed anything, so the feed says what did.
  test 'what it releases is in the activity of each submission' do
    sample = samples(:first)
    row    = dra_with([part_of('db' => 'sample', 'accession' => sample.accession)])

    HoldDateRelease.call(today: @today)

    assert_equal 'hold date set 1 DRA submission to public', row.submission.curation_events.sole.then { "#{it.actor_label} #{it.summary}" }
    assert_equal "with #{row.accession} set 1 sample to public", sample.submission.curation_events.sole.then { "#{it.actor_label} #{it.summary}" }
  end

  test 'leaves what is not due yet, or has no date' do
    project = projects(:primary)
    project.update!(hold_date: @today + 1)

    HoldDateRelease.call(today: @today)

    assert project.reload.status_private?

    project.update!(hold_date: nil)

    HoldDateRelease.call(today: @today)

    assert project.reload.status_private?
  end

  # D-way cleared the date on release. Here it stays, so a row a curator
  # has taken out of public since must not be put back by it.
  test 'a hold date releases once' do
    project = projects(:primary)
    project.update!(hold_date: @today)

    HoldDateRelease.call(today: @today)
    Project.where(id: project).move_to_status!('temporarily_suppressed')
    HoldDateRelease.call(today: @today + 1)

    assert project.reload.status_temporarily_suppressed?
  end

  # D-way releases what it still holds, and its import would bring the
  # status back.
  test 'releases nothing until D-way has handed over' do
    DwayTakeover.delete_all

    projects(:primary).update!(hold_date: @today)
    sample = samples(:first)
    row    = dra_with([part_of('db' => 'sample', 'accession' => sample.accession)])

    HoldDateRelease.call(today: @today)

    assert projects(:primary).reload.status_private?
    assert row.reload.status_private?

    # Nor does a DRA submission published by hand take anything along.
    DRASubmission.where(id: row).move_to_status!('public')

    assert sample.reload.status_private?
  end

  # A sample held "until the release of linked data" is released by
  # nothing else.
  test 'a DRA submission takes along the projects and samples its experiments are part of' do
    sample = samples(:first)
    sample.update!(status: :curating)

    row = dra_with([
      part_of('db' => 'sample', 'accession' => sample.accession),
      part_of('db' => 'project', 'id' => 'own-project')
    ])

    assert_equal 1, HoldDateRelease.call(today: @today).dra_submissions

    assert row.reload.status_public?
    assert sample.reload.status_public?, "D-way's numbered rows are imported as curating"
    assert projects(:primary).reload.status_public?, 'named by alias, found in the record'
  end

  # Not only by its hold date: however it is published.
  test 'a DRA submission a curator publishes takes them along too' do
    row = dra_with([part_of('db' => 'sample', 'accession' => samples(:first).accession)], hold_date: nil)

    DRASubmission.where(id: row).move_to_status!('public')

    assert samples(:first).reload.status_public?
  end

  test 'what is out of the way stays there' do
    sample = samples(:first)
    sample.update!(status: :withdrawn)

    row = dra_with([part_of('db' => 'sample', 'accession' => sample.accession)])

    HoldDateRelease.call(today: @today)

    assert row.reload.status_public?
    assert sample.reload.status_withdrawn?
  end

  # An experiment naming someone else's accession must not publish it.
  test "another submitter's sample is not taken along" do
    theirs = Submission.create!(db: 'biosample', user: users(:carol)).samples.create!(sample_name: 'theirs', status: :private, accession: 'SAMD00000999')

    row = dra_with([part_of('db' => 'sample', 'accession' => theirs.accession)])

    assert_error_reported(DRA::LinkedRelease::Withheld) do
      HoldDateRelease.call(today: @today)
    end

    assert row.reload.status_public?
    assert theirs.reload.status_private?
  end

  # One record that cannot be read holds back nothing else, and releases
  # nothing of its own: the next run tries it again. The run says so.
  test 'a DRA submission whose record cannot be read is left for the next run' do
    broken = dra_with([part_of('db' => 'sample', 'accession' => samples(:first).accession)])
    other  = another_dra.tap { it.update!(hold_date: @today) }

    SubmissionUpdate.create_with_patch!(
      submission:              broken.submission,
      patch_json:              'not-json',
      db:                      'dra',
      status:                  :applied,
      actor:                   'test',
      source:                  :manual,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    error = assert_raises(HoldDateRelease::Incomplete) { HoldDateRelease.call(today: @today) }

    assert_includes error.message, broken.accession
    assert broken.reload.status_private?
    assert samples(:first).reload.status_private?
    assert other.reload.status_public?
  end

  test 'run again, it releases nothing more' do
    projects(:primary).update!(hold_date: @today)
    dra_with([])

    HoldDateRelease.call(today: @today)

    assert_no_enqueued_emails do
      assert_equal [0, 0], HoldDateRelease.call(today: @today).to_h.values_at(:projects, :dra_submissions)
    end
  end
end
