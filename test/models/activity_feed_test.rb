require 'test_helper'

class ActivityFeedTest < ActiveSupport::TestCase
  setup do
    @request = submission_requests(:bioproject)
  end

  def entries = ActivityFeed.new(@request).entries

  test 'the request itself is always the oldest entry' do
    assert_equal 'submitted this request', entries.last.summary
    assert_equal users(:alice).uid,        entries.last.actor
  end

  test 'a migration-sourced request says so instead of naming a submitter action' do
    @request.update_column(:migration_run_id, SecureRandom.uuid)

    assert_equal 'was created by a migration run', entries.last.summary
  end

  test 'messages read as who spoke to whom' do
    @request.messages.create!(user: users(:bob),   author_role: 'curator',   body: 'please clarify')
    @request.messages.create!(user: users(:alice), author_role: 'submitter', body: 'here you go')

    summaries = entries.map(&:summary)

    assert_includes summaries, 'posted a message to the submitter'
    assert_includes summaries, 'replied to the curator'
  end

  # Chain rows carry namespaced actors ("admin:tanaka"); a sentence should
  # name the person, not the namespace.
  test 'chain entries name the actor and carry the patch id as a reference' do
    update = submissions(:bioproject).append_update!({'project' => {'title' => 'x'}}, actor: 'admin:tanaka')

    entry = entries.find { it.update_id == update.id }

    assert_equal 'tanaka',              entry.actor
    assert_equal 'edited the record',   entry.summary
  end

  test 'a TSV import reports its row and error counts' do
    submissions(:bioproject).sample_tsv_imports.create!(
      actor: 'admin:tanaka', started_at: Time.current, finished_at: Time.current,
      status: 'completed', processed: 1842, failed: 0
    )

    assert_includes entries.map(&:summary), 'uploaded a sample TSV — 1,842 rows, 0 errors'
  end

  # The line the mockup keeps but the patch chain cannot supply: a bulk
  # status change leaves no snapshot, so it carries no reference.
  test 'curation events appear as sentences with no patch reference' do
    CurationEvent.record!(
      submission: submissions(:bioproject),
      actor:      'admin:tanaka',
      action:     :curation_updated,
      row_count:  1842,
      noun:       'sample',
      status:     'curating'
    )

    entry = entries.find { it.summary.start_with?('set ') }

    assert_equal 'tanaka',                        entry.actor
    assert_equal 'set 1,842 samples to curating', entry.summary
    assert_nil   entry.update_id, 'a non-record action has no snapshot to link to'
  end

  test 'accession issuance shows up even though it produces no patch' do
    projects(:primary).update!(accession: nil, status: 'curating')

    AccessionIssue.call(submission: submissions(:bioproject), actor: 'admin:tanaka')

    assert_includes entries.map(&:summary), 'issued 1 PRJDB accession'
  end

  test 'entries are newest first and bounded' do
    5.times {|i| @request.messages.create!(user: users(:bob), author_role: 'curator', body: "m#{i}") }

    list = ActivityFeed.new(@request).entries(limit: 3)

    assert_equal 3, list.size
    assert_operator list.first.at, :>=, list.last.at
  end
end
