require 'test_helper'

class LifecycleableTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test 'status enum maps all 9 codes (5100..5900) with prefix' do
    expected = {
      'submission_accepted'    => 5100,
      'curating'               => 5200,
      'accession_issued'       => 5300,
      'private'                => 5400,
      'public'                 => 5500,
      'withdrawn'              => 5600,
      'canceled'               => 5700,
      'permanently_suppressed' => 5800,
      'temporarily_suppressed' => 5900
    }

    assert_equal expected, Project.statuses
    assert_equal expected, Sample.statuses
  end

  test 'predicates use status_ prefix to avoid shadowing reserved words' do
    project = projects(:primary)

    assert project.respond_to?(:status_private?)
    assert project.respond_to?(:status_public?)
    assert_not project.respond_to?(:private?)
  end

  # DRAFT (Spike 0.8): pins current behavior. Update when curator policy is set.
  test 'publicly_visible only exposes status=public' do
    Project.statuses.each_key do |status|
      Project.update_all(status: Project.statuses[status])

      if status == 'public'
        assert_equal Project.count, Project.publicly_visible.count, "Expected #{status} to be publicly visible"
      else
        assert_equal 0, Project.publicly_visible.count, "Expected #{status} NOT to be publicly visible"
      end
    end
  end

  test 'curator_visible excludes canceled and withdrawn' do
    invisible = %w[canceled withdrawn]
    visible   = Project.statuses.keys - invisible

    visible.each do |status|
      Project.update_all(status: Project.statuses[status])
      assert_equal Project.count, Project.curator_visible.count, "Expected #{status} to be curator-visible"
    end

    invisible.each do |status|
      Project.update_all(status: Project.statuses[status])
      assert_equal 0, Project.curator_visible.count, "Expected #{status} NOT to be curator-visible"
    end
  end

  # One statement over rows in different states, each judged by the status
  # it had: only a row crossing into or out of public is dated.
  test 'move_to_status! dates only the rows that cross public' do
    submission = submissions(:biosample)
    was_public = submission.samples.create!(sample_name: 'was-public', status: :public, first_published_at: 1.year.ago, last_published_at: 1.year.ago)
    never      = submission.samples.create!(sample_name: 'never', status: :private)
    now        = Time.zone.local(2026, 10, 1, 10)

    Sample.where(id: [was_public, never]).move_to_status!('temporarily_suppressed', at: now)

    assert_equal now, was_public.reload.last_published_at
    assert_nil        never.reload.last_published_at
    assert_equal %w[temporarily_suppressed temporarily_suppressed], [was_public.status, never.status]
  end

  # ST.26 entries keep no publication timestamps; their status moves all
  # the same.
  test 'move_to_status! on rows that keep no timestamps moves the status alone' do
    entries = submissions(:st26).entries

    assert_not Entry.publication_tracked?

    entries.move_to_status!('withdrawn')

    assert entries.reload.all?(&:status_withdrawn?)
  end

  # The first time a submission's rows are made public its submitter is
  # told, in the thread and by mail — once a submission, however many rows.
  test 'move_to_status! announces a first publication, one notice a submission' do
    submission = submissions(:biosample)
    first      = submission.samples.create!(sample_name: 'first', status: :private, accession: 'SAMD00000101')
    second     = submission.samples.create!(sample_name: 'second', status: :private, accession: 'SAMD00000102')

    Sample.where(id: [first, second]).joins(:submission).move_to_status!('public')

    notice = submission.request.messages.system_role.sole

    assert_enqueued_email_with SubmissionNoticeMailer, :published, params: {notice:, first: 'SAMD00000101', count: 2}

    assert_includes notice.body, "2 samples of your BioSample submission (##{submission.request.id}) are now public."
    assert_includes notice.body, '  - SAMD00000101  first'
    assert_includes notice.body, '  - SAMD00000102  second'
  end

  # Only the first time: a row back out of suppression was announced when
  # it first went out, and one public already is not news.
  test 'move_to_status! does not announce a row published before' do
    submission = submissions(:biosample)
    again      = submission.samples.create!(sample_name: 'again', status: :temporarily_suppressed, accession: 'SAMD00000103', first_published_at: 1.year.ago)
    already    = submission.samples.create!(sample_name: 'already', status: :public, accession: 'SAMD00000104', first_published_at: 1.year.ago)

    # Public without the date, as rows written before it was kept are.
    undated = submission.samples.create!(sample_name: 'undated', status: :public, accession: 'SAMD00000106')

    assert_no_enqueued_emails do
      Sample.where(id: [again, already, undated]).move_to_status!('public')
    end

    assert_not submission.request.messages.exists?
  end

  # The status and its notice are one: several screens call this with no
  # transaction open, and a status committed without its notice would
  # never be announced — the row is first-published from then on.
  test 'move_to_status! takes the status back when its notice cannot be posted' do
    sample = submissions(:biosample).samples.create!(sample_name: 'unannounced', status: :private, accession: 'SAMD00000107')

    SubmissionNotice.stub(:published!, ->(*) { raise 'simulated failure' }) do
      assert_raises(RuntimeError) { Sample.where(id: sample).move_to_status!('public') }
    end

    assert_equal ['private', nil], [sample.reload.status, sample.first_published_at]
  end

  # The notice in the thread is the record; a queue that is down must not
  # turn a publication already committed into an error.
  test 'move_to_status! publishes when the mail cannot be queued' do
    sample = submissions(:biosample).samples.create!(sample_name: 'unmailed', status: :private, accession: 'SAMD00000108')

    SubmissionNoticeMailer.stub(:with, ->(**) { raise ActiveRecord::ConnectionNotEstablished, 'queue is down' }) do
      Sample.where(id: sample).move_to_status!('public')
    end

    assert sample.reload.status_public?
    assert sample.submission.request.messages.system_role.exists?
  end

  # A notice rolled back with the status it announced was never mailed.
  test 'move_to_status! mails the announcement only once it is committed' do
    sample = submissions(:biosample).samples.create!(sample_name: 'rolled-back', status: :private, accession: 'SAMD00000105')

    assert_no_enqueued_emails do
      Sample.transaction do
        Sample.where(id: sample).move_to_status!('public')

        raise ActiveRecord::Rollback
      end
    end
  end

  # `update_all` over a join writes through an alias of the same table, where
  # a bare column name is ambiguous.
  test 'move_to_status! works over a joined relation' do
    sample = submissions(:biosample).samples.create!(sample_name: 'joined', status: :private)

    Sample.where(id: sample).joins(:submission).move_to_status!('public')

    assert sample.reload.first_published_at
  end
end
