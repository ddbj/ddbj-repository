require 'test_helper'

class LifecycleableTest < ActiveSupport::TestCase
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
end
