require 'test_helper'

class SampleReferenceTest < ActiveSupport::TestCase
  test 'requires known ref_db' do
    ref = SampleReference.new(sample: samples(:first), ref_db: 'unknown', ref_accession: 'X')

    assert_not ref.valid?
    assert_includes ref.errors[:ref_db], 'is not included in the list'
  end

  test 'rejects bioproject accession that does not match PRJD[B-Z]\d+' do
    ref = SampleReference.new(sample: samples(:first), ref_db: 'bioproject', ref_accession: 'PRJNA123')

    assert_not ref.valid?
    assert_includes ref.errors[:ref_accession], 'is not a valid bioproject accession'
  end

  test 'accepts SRA accession matching [DES]R[APRSXZ]\d+' do
    ref = SampleReference.new(sample: samples(:first), ref_db: 'sra', ref_accession: 'DRS000123')

    assert ref.valid?
  end

  test 'dra accepts D[A-Z]{2}\d+ and rejects shorter forms' do
    {'DRA000123' => true, 'DRR999' => true, 'DR123' => false, 'DRAB12' => false}.each do |acc, expected|
      ref = SampleReference.new(sample: samples(:first), ref_db: 'dra', ref_accession: acc)
      assert_equal expected, ref.valid?, "Expected #{acc} validity to be #{expected}"
    end
  end

  test 'gea requires E-GEAD- prefix' do
    {'E-GEAD-12345' => true, 'GEAD-12345' => false, 'E-GEAB-1' => false}.each do |acc, expected|
      ref = SampleReference.new(sample: samples(:first), ref_db: 'gea', ref_accession: acc)
      assert_equal expected, ref.valid?, "Expected #{acc} validity to be #{expected}"
    end
  end

  test 'ref_accession presence required' do
    ref = SampleReference.new(sample: samples(:first), ref_db: 'bioproject', ref_accession: nil)

    assert_not ref.valid?
    assert_includes ref.errors[:ref_accession], "can't be blank"
  end

  test 'unique on (sample_id, ref_db, ref_accession)' do
    sample = samples(:first)

    SampleReference.create!(sample:, ref_db: 'gea', ref_accession: 'E-GEAD-99999')

    dup = SampleReference.new(sample:, ref_db: 'gea', ref_accession: 'E-GEAD-99999')

    assert_raises ActiveRecord::RecordNotUnique do
      dup.save validate: false
    end
  end
end
