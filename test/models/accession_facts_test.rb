require 'test_helper'

class AccessionFactsTest < ActiveSupport::TestCase
  test 'a BioProject is its title, and what kind of project it is' do
    facts = AccessionFacts.for(projects(:primary))

    assert_equal 'PRJDB000001',             facts.accession
    assert_equal 'bioproject',              facts.db
    assert_equal 'Primary fixture project', facts.name
    assert_equal [{label: 'Type', value: 'primary'}], facts.details
  end

  test 'a BioSample is its name, and the facts its own columns carry' do
    facts = AccessionFacts.for(samples(:first))

    assert_equal 'SAMD00000001',     facts.accession
    assert_equal 'biosample',        facts.db
    assert_equal 'fixture-sample-1', facts.name

    # Blank columns are dropped rather than drawn empty — this sample has
    # no title, organism or taxonomy id.
    assert_equal [{label: 'Package', value: 'Generic.1.0'}], facts.details
  end

  test 'an ST.26 entry is its entry id, its version and its LOCUS date' do
    facts = AccessionFacts.for(entries(:one))

    assert_equal 'ACC_000001',            facts.accession
    assert_equal 'st26',                  facts.db
    assert_equal 'SEQ|JP|2026123456|A|1', facts.name

    assert_equal(
      [
        {label: 'Version',    value: '1'},
        {label: 'LOCUS date', value: '2026-01-15'}
      ],
      facts.details
    )
  end

  # Nothing else is an accessioned row, and being handed one is a
  # programming mistake rather than a state to render.
  test 'anything else is refused' do
    assert_raises ArgumentError do
      AccessionFacts.for(submissions(:bioproject))
    end
  end
end
