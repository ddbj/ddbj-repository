require 'test_helper'

class LiveList::ExporterTest < ActiveSupport::TestCase
  setup do
    @output_dir     = Pathname.new(Dir.mktmpdir)
    @submission_ids = []
  end

  teardown do
    @output_dir.rmtree if @output_dir&.exist?
  end

  # One Project per Submission (has_one), so each needs its own source_id.
  def project(accession:, status:, modified_date: nil)
    submission = Submission.create!(db: :bioproject, source_id: "PSUB-#{accession}", user: users(:alice))
    @submission_ids << submission.id

    Project.create!(submission:, project_type: :primary, status:, accession:, modified_date:)
  end

  # Scoped to this test's own rows so the exact-content assertions are not
  # perturbed by fixture projects.
  def run_exporter
    LiveList::Exporter.new(
      output_dir:      @output_dir,
      filename_prefix: 'bioproject',
      scope:           Project.where(submission_id: @submission_ids, status: LiveList::Exporter::LISTED_STATUSES).where.not(accession: nil)
    ).call
  end

  def rows(label)
    @output_dir.join("bioproject.#{label}.txt").readlines(chomp: true).map { it.split("\t") }
  end

  test 'partitions records into public / suppressed / withdrawn files with a header' do
    project(accession: 'PRJDB2',  status: :public,                 modified_date: Date.new(2020, 3, 30))
    project(accession: 'PRJDB51', status: :temporarily_suppressed, modified_date: Date.new(2025, 7, 23))
    project(accession: 'PRJDB60', status: :permanently_suppressed, modified_date: Date.new(2024, 1, 2))
    project(accession: 'PRJDB70', status: :withdrawn,              modified_date: Date.new(2016, 7, 4))

    # Excluded statuses must not appear anywhere.
    project(accession: 'PRJDB80', status: :private)
    project(accession: 'PRJDB90', status: :canceled)
    project(accession: 'PRJDB91', status: :curating)

    run_exporter

    assert_equal %w[Accession Updated Status], rows('public').first
    assert_equal ['PRJDB2', '2020-03-30', 'public'], rows('public')[1]

    # temporarily + permanently suppressed collapse to `suppressed`.
    assert_equal [%w[PRJDB51 2025-07-23 suppressed], %w[PRJDB60 2024-01-02 suppressed]], rows('suppressed')[1..]

    assert_equal [%w[PRJDB70 2016-07-04 withdrawn]], rows('withdrawn')[1..]

    # Excluded accessions appear in none of the files.
    body = LiveList::Exporter::LABELS.flat_map { rows(it) }.flatten.join(' ')
    %w[PRJDB80 PRJDB90 PRJDB91].each { assert_not_includes body, it }
  end

  test 'orders rows by accession (index-backed keyset)' do
    # Inserted out of order; the livelist comes out sorted by accession.
    %w[PRJDB000773 PRJDB000771 PRJDB000772].each do |acc|
      project(accession: acc, status: :public)
    end

    run_exporter

    assert_equal %w[PRJDB000771 PRJDB000772 PRJDB000773], rows('public')[1..].map(&:first)
  end

  test 'Updated falls back to updated_at when modified_date is absent' do
    project(accession: 'PRJDB2', status: :public, modified_date: nil)

    run_exporter

    assert_equal Date.current.iso8601, rows('public')[1][1]
  end

  test 'writes all three files atomically (final present, no .partial left)' do
    project(accession: 'PRJDB2', status: :public)

    run_exporter

    LiveList::Exporter::LABELS.each do |label|
      assert @output_dir.join("bioproject.#{label}.txt").exist?
      assert_not @output_dir.join("bioproject.#{label}.txt.partial").exist?
    end
  end
end
