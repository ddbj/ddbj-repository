require 'test_helper'

class BioSample::ConverterTest < ActiveSupport::TestCase
  C  = BioSample::Converter
  SC = BioSample::StagingClient

  def build_submission(samples:, contacts: [], comment: '[2014] Test submission', organization: 'Sample Organization', organization_url: nil)
    SC::Submission.new(
      ssub_id:          'SSUB-test',
      submitter_id:     'sample-uid',
      organization:     organization,
      organization_url: organization_url,
      comment:          comment,
      contacts:         contacts,
      samples:          samples
    )
  end

  def sample(smp_id: 1, accession: 'SAMD00099999', alias_name: 'DRS999999', package: 'Generic', package_group: nil, env_package: nil, status_id: 5500, attributes: [])
    SC::Sample.new(
      smp_id:        smp_id,
      accession:     accession,
      sample_name:   alias_name,
      package:       package,
      package_group: package_group,
      env_package:   env_package,
      status_id:     status_id,
      attributes:    attributes
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

    assert_equal 'v3',                               record['schema_version']
    assert_equal({'source_format' => 'dway_bs_eav'}, record['provenance'])

    # Staging's `comment` column is now carried by the Importer onto a
    # typed Submission#curator_comment AR column, NOT lifted into v3.
    refute_includes Array(record['submission']&.keys), 'comments',
                    'D-way comment must not leak into v3 submission.comments'

    sample_v3 = record.fetch('samples').first
    assert_equal 'SAMD00099999',                                              sample_v3['accession']
    assert_equal 'DRS999999',                                                 sample_v3['alias']
    assert_equal 'Generic',                                                   sample_v3['package']
    assert_equal 'APr03S00',                                                  sample_v3['title']
    assert_equal({'taxonomy_id' => 408170, 'name' => 'human gut metagenome'}, sample_v3['organism'])
    assert_equal 4,                                                           sample_v3['attributes'].size
  end

  test 'lifts contacts into submission.submitters carrying the shared organization' do
    sub = build_submission(
      organization:     'Sample Organization 1',
      organization_url: 'https://example.test/org-1',
      samples:          [sample],
      contacts:         [
        SC::Contact.new(email: 'sample-1@example.test', first: 'Sample-First-1', last: 'Sample-Last-1'),
        SC::Contact.new(email: nil,                     first: 'Sample-First-2', last: nil)
      ]
    )

    submitters = C.new(submission: sub).call.dig('submission', 'submitters')

    expected_org = {'name' => 'Sample Organization 1', 'url' => 'https://example.test/org-1'}
    assert_equal 2, submitters.size
    assert_equal({'email'         => 'sample-1@example.test',
                  'first_name'    => 'Sample-First-1',
                  'last_name'     => 'Sample-Last-1',
                  'organizations' => [expected_org]}, submitters[0])
    assert_equal({'first_name'    => 'Sample-First-2',
                  'organizations' => [expected_org]}, submitters[1])
  end

  test 'drops Contact fields that arrive as empty strings (PG SQL NULL surrogate)' do
    sub = build_submission(
      organization: nil,
      samples:      [sample],
      contacts:     [
        # All-empty contact must drop entirely.
        SC::Contact.new(email: '', first: '', last: ''),
        # Partially-empty contact must keep only non-empty fields.
        SC::Contact.new(email: '', first: 'Sample-First', last: '')
      ]
    )

    submitters = C.new(submission: sub).call.dig('submission', 'submitters')

    assert_equal 1, submitters.size, 'all-empty contact must drop'
    assert_equal({'first_name' => 'Sample-First'}, submitters[0],
                 'empty-string fields must not survive as "" in v3 record')
  end

  test 'omits organizations key entirely when staging has neither name nor url' do
    sub = build_submission(
      organization:     nil,
      organization_url: nil,
      samples:          [sample],
      contacts:         [SC::Contact.new(email: 'x@example.test', first: 'X', last: 'Y')]
    )

    submitter = C.new(submission: sub).call.dig('submission', 'submitters', 0)
    refute_includes submitter.keys, 'organizations'
  end

  test 'never lifts the staging comment into v3 submission.comments (curator_comment is typed-column)' do
    ['', '   ', 'a real comment', "multi\nline"].each do |value|
      sub = build_submission(
        comment:  value,
        samples:  [sample],
        contacts: [SC::Contact.new(email: 'x@example.test', first: 'X', last: 'Y')] # keeps submission block non-empty
      )
      submission = C.new(submission: sub).call.fetch('submission')

      refute_includes submission.keys, 'comments',
                      "comment value #{value.inspect} must never produce a `comments` key — the v3 slot is reserved for legitimate (e.g. Trad) commentary"
    end
  end

  test 'lifts description from EAV into Sample.description (value also stays in attributes bag)' do
    sub = build_submission(samples: [sample(attributes: [
      {'name' => 'sample_name', 'value' => 'DRS999999'},
      {'name' => 'description', 'value' => 'Liver biopsy from healthy donor'}
    ])])

    sample_v3 = C.new(submission: sub).call.dig('samples', 0)

    assert_equal 'Liver biopsy from healthy donor', sample_v3['description'],
                 'EAV `description` must lift into v3 Sample.description'
    assert_includes sample_v3['attributes'],
                    {'name' => 'description', 'value' => 'Liver biopsy from healthy donor'},
                    'lifted attribute must also survive in the bag (mirrors the title / organism lift convention)'
  end

  test 'blank-valued description EAV does NOT produce a description key' do
    sub = build_submission(samples: [sample(attributes: [
      {'name' => 'sample_name', 'value' => 'DRS999999'},
      {'name' => 'description', 'value' => ''}
    ])])

    sample_v3 = C.new(submission: sub).call.dig('samples', 0)

    refute_includes sample_v3.keys, 'description',
                    "blank `description` EAV must drop the key (mirrors title's .presence chain)"
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
