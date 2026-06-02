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
end
