require 'test_helper'

class PublishBpLiveListJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('collab').tap(&:mkpath)
  end

  teardown do
    @output_dir.glob('bioproject.*.txt*').each(&:delete)
  end

  def project(source_id:, accession:, status:, modified_date: nil)
    submission = Submission.create!(db: :bioproject, source_id:, user: users(:alice))

    Project.create!(submission:, project_type: :primary, status:, accession:, modified_date:)
  end

  test 'writes the three BP livelist files to the collab dir' do
    project(source_id: 'PSUB-a', accession: 'PRJDB2',  status: :public,                 modified_date: Date.new(2020, 3, 30))
    project(source_id: 'PSUB-b', accession: 'PRJDB51', status: :temporarily_suppressed, modified_date: Date.new(2025, 7, 23))
    project(source_id: 'PSUB-c', accession: 'PRJDB80', status: :private) # excluded

    PublishBpLiveListJob.perform_now

    public_file = @output_dir.join('bioproject.public.txt')
    assert public_file.exist?
    assert_equal %w[Accession Updated Status], public_file.readlines(chomp: true).first.split("\t")
    assert_includes public_file.read, "PRJDB2\t2020-03-30\tpublic"

    assert_includes @output_dir.join('bioproject.suppressed.txt').read, "PRJDB51\t2025-07-23\tsuppressed"

    # Private project is listed nowhere.
    assert_not_includes @output_dir.join('bioproject.public.txt').read, 'PRJDB80'
  end
end
