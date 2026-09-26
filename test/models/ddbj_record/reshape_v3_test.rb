require 'test_helper'

class DDBJRecord::ReshapeV3Test < ActiveSupport::TestCase
  R = DDBJRecord::ReshapeV3

  test 'a project becomes the one element of projects, and a taxonomy_id a string' do
    record = {
      'project' => {'title' => 't', 'organism' => {'taxonomy_id' => 9606, 'name' => 'Homo sapiens'}},
      'samples' => [{'alias' => 's1', 'organism' => {'taxonomy_id' => 408170}}]
    }

    assert_equal({
      'samples'  => [{'alias' => 's1', 'organism' => {'taxonomy_id' => '408170'}}],
      'projects' => [{'title' => 't', 'organism' => {'taxonomy_id' => '9606', 'name' => 'Homo sapiens'}}]
    }, R.call(record))
  end

  # What BioProject::Converter wrote before LocusTagPrefix carried its
  # BioSample. Which data_types values were ProjectDataTypeSet's cannot be
  # told from the record, so they stay where they are.
  test 'an early BioProject record is put in the converter\'s current shape' do
    record = {'project' => {'locus_tag_prefix' => ['ABC'], 'target' => {'data_types' => ['eSequence', 'Genome Sequencing']}}}

    project = R.call(record).dig('projects', 0)

    assert_equal [{'prefix' => 'ABC'}], project['locus_tag_prefix']
    assert_equal ['eSequence', 'Genome Sequencing'], project.dig('target', 'data_types')
  end

  test 'refuses a record that has both project and projects' do
    assert_raises(R::Error) { R.call({'project' => {}, 'projects' => [{}]}) }
  end

  test 'a record in the current shape is left as it is' do
    record = {
      'projects' => [{
        'locus_tag_prefix' => [{'prefix' => 'ABC', 'biosample_id' => 'SAMD00000001'}],
        'organism'         => {'taxonomy_id' => '009606'},
        'target'           => {'data_types' => ['eOther']},
        'attributes'       => [{'name' => 'project_data_type', 'value' => 'Genome Sequencing'}]
      }]
    }

    assert_equal record, R.call(record)
    assert_equal R.call(record), R.call(R.call(record))
  end

  # The importers compare a new conversion against the checksum an import
  # took before the change, so the old shape has to come back byte for byte.
  test 'old_shape is the converter output as the converter wrote it before' do
    xml = file_fixture('data_migration/bio_project/PSUB000604.xml').read
    now = BioProject::Converter.new(xml:, project_row: {project_type: 'primary', accession: 'PRJDB502'}).call

    old = R.old_shape(now)

    assert_equal now.keys.map { it == 'projects' ? 'project' : it }, old.keys
    assert_equal Integer(now.dig('projects', 0, 'organism', 'taxonomy_id')), old.dig('project', 'organism', 'taxonomy_id')
    assert_equal R.call(old).dig('projects', 0, 'organism'), now.dig('projects', 0, 'organism')
  end

  test 'old_shape drops a taxonomy_id that is not a number, and an organism left empty' do
    now = {'samples' => [{'alias' => 's1', 'organism' => {'taxonomy_id' => 'unknown'}}, {'alias' => 's2', 'organism' => {'taxonomy_id' => 'x', 'name' => 'n'}}]}

    assert_equal({'samples' => [{'alias' => 's1'}, {'alias' => 's2', 'organism' => {'name' => 'n'}}]}, R.old_shape(now))
  end
end
