require 'test_helper'

class BioSample::ConverterTest < ActiveSupport::TestCase
  C  = BioSample::Converter
  SC = BioSample::StagingClient

  def build_submission(samples:, contacts: [], comment: '[2014] Test submission')
    SC::Submission.new(
      ssub_id:      'SSUB-test',
      submitter_id: 'sample-uid',
      organization: 'Sample Organization',
      comment:      comment,
      contacts:     contacts,
      samples:      samples
    )
  end

  def sample(smp_id: 1, accession: 'SAMD00099999', alias_name: 'DRS999999', package: 'Generic', status_id: 5500, attributes: [])
    SC::Sample.new(
      smp_id:      smp_id,
      accession:   accession,
      sample_name: alias_name,
      package:     package,
      status_id:   status_id,
      attributes:  attributes
    )
  end

  test 'minimum: a single Generic sample with organism + title produces a v3 record' do
    sub = build_submission(samples: [sample(attributes: [
      {'name' => 'sample_name',  'value' => 'DRS999999'},
      {'name' => 'organism',     'value' => 'human gut metagenome'},
      {'name' => 'taxonomy_id',  'value' => '408170'},
      {'name' => 'sample_title', 'value' => 'APr03S00'}
    ])])

    record = C.new(submission: sub).call

    assert_equal 'v3',                                record['schema_version']
    assert_equal({'source_format' => 'dway_bs_eav'}, record['provenance'])
    assert_equal '[2014] Test submission',            record.dig('submission', 'comments')

    sample_v3 = record.fetch('samples').first
    assert_equal 'SAMD00099999',                                              sample_v3['accession']
    assert_equal 'DRS999999',                                                 sample_v3['alias']
    assert_equal 'Generic',                                                   sample_v3['package']
    assert_equal 'APr03S00',                                                  sample_v3['title']
    assert_equal({'taxonomy_id' => 408170, 'name' => 'human gut metagenome'}, sample_v3['organism'])
    assert_equal 4,                                                           sample_v3['attributes'].size
  end

  test 'lifts contacts into submission.submitters and skips blank values' do
    sub = build_submission(
      samples:  [sample],
      contacts: [
        SC::Contact.new(email: 'sample-1@example.test', first: 'Sample-First-1', last: 'Sample-Last-1'),
        SC::Contact.new(email: nil,                     first: 'Sample-First-2', last: nil)
      ]
    )

    submitters = C.new(submission: sub).call.dig('submission', 'submitters')

    assert_equal 2, submitters.size
    assert_equal({'email' => 'sample-1@example.test', 'first' => 'Sample-First-1', 'last' => 'Sample-Last-1'}, submitters[0])
    assert_equal({'first' => 'Sample-First-2'},                                                                submitters[1])
  end

  test 'N samples in samples array preserve staging order' do
    sub = build_submission(samples: (1..5).map {|i|
      sample(smp_id: i, accession: "SAMD0000000#{i}", alias_name: "DRS00000#{i}")
    })

    record = C.new(submission: sub).call
    assert_equal %w[SAMD00000001 SAMD00000002 SAMD00000003 SAMD00000004 SAMD00000005],
                 record['samples'].map {|s| s['accession'] }
  end

  test 'non-numeric taxonomy_id drops rather than silently becoming 0' do
    sub = build_submission(samples: [sample(attributes: [
      {'name' => 'organism',    'value' => 'unknown organism'},
      {'name' => 'taxonomy_id', 'value' => 'unknown'}
    ])])

    organism = C.new(submission: sub).call.dig('samples', 0, 'organism')

    assert_equal({'name' => 'unknown organism'}, organism,
                 "expected taxonomy_id to drop (was 'unknown'); got #{organism.inspect}")
  end

  test 'canonicalises cleanly via the production pipeline' do
    sub = build_submission(samples: [sample(attributes: [
      {'name' => 'sample_name', 'value' => 'DRS999999'},
      {'name' => 'organism',    'value' => 'human gut metagenome'},
      {'name' => 'taxonomy_id', 'value' => '408170'}
    ])])

    bytes = DDBJRecord::Canonicalizer.canonicalize(C.new(submission: sub).call)

    assert_kind_of String, bytes
    assert_includes bytes, '"accession":"SAMD00099999"'
  end
end
