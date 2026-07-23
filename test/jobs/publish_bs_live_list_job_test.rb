require 'test_helper'

class PublishBsLiveListJobTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('collab').tap(&:mkpath)
  end

  teardown do
    @output_dir.glob('biosample.*.txt*').each(&:delete)
  end

  test 'writes the three BS livelist files partitioned by status' do
    submission = Submission.create!(db: :biosample, source_id: 'SSUB-livelist', user: users(:alice))
    submission.samples.create!(accession: 'SAMD00099992', sample_name: 'DRS2', status: :public,    modified_date: Date.new(2022, 4, 5))
    submission.samples.create!(accession: 'SAMD00099991', sample_name: 'DRS1', status: :public,    modified_date: Date.new(2022, 4, 5))
    submission.samples.create!(accession: 'SAMD00099993', sample_name: 'DRS3', status: :withdrawn, modified_date: Date.new(2025, 10, 9))
    submission.samples.create!(accession: 'SAMD00099994', sample_name: 'DRS4', status: :curating) # excluded

    PublishBsLiveListJob.perform_now

    public_file = @output_dir.join('biosample.public.txt')
    assert_equal %w[Accession Updated Status], public_file.readlines(chomp: true).first.split("\t")
    assert_includes public_file.read, "SAMD00099991\t2022-04-05\tpublic"

    # This submission's two public samples come out in accession order.
    mine = public_file.readlines(chomp: true)[1..].map { it.split("\t").first }.grep(/SAMD0009999/)
    assert_equal %w[SAMD00099991 SAMD00099992], mine

    assert_includes @output_dir.join('biosample.withdrawn.txt').read, "SAMD00099993\t2025-10-09\twithdrawn"
    assert_not_includes public_file.read, 'SAMD00099994'
  end
end
