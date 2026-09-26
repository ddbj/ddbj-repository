# frozen_string_literal: true

module DDBJRecord
  # The shape the spec's v3 took at ddbj/ddbj-record-specifications#11, for
  # records the repository wrote before it:
  #
  #   - `project` (one object) became `projects` (a list; a BioProject's
  #     record holds one)
  #   - `taxonomy_id` is the string as written, not an integer
  #
  # and two things BioProject::Converter wrote differently before it told
  # them apart (2026-08-27): LocusTagPrefix as bare strings, and
  # ProjectDataTypeSet values mixed into `target.data_types`.
  #
  # `call` rewrites a stored record into the current shape (rake
  # ddbj_record:reshape_v3). `old_shape` goes the other way for a converter's
  # output, so the importers can still recognise an unchanged source by the
  # checksum taken before the change (Submission#same_source?).
  module ReshapeV3
    # The Objectives/Data@data_type vocabulary; ProjectDataTypeSet uses
    # another ("Genome Sequencing", …).
    OBJECTIVE_DATA_TYPES = %w[
      eRawSequenceReads eSequence eAnalysis eAssembly eAnnotation eVariation
      eEpigeneticMarkers eExpression eMaps ePhenotype eOther
    ].to_set.freeze

    module_function

    def call(record)
      record = record.deep_dup

      if record.key?('project')
        project = record.delete('project')
        record['projects'] = [project] if project.present?
      end

      Array(record['projects']).each do |project|
        stringify_taxonomy_id!(project['organism'])
        objectify_locus_tag_prefixes!(project)
        separate_project_data_types!(project)
      end

      Array(record['samples']).each do |sample|
        stringify_taxonomy_id!(sample['organism'])
      end

      record
    end

    # A converter's output as the converters wrote it before the change —
    # `project` for `projects`, taxonomy_id an integer or absent — keeping
    # every key in its place, since the checksum is of the serialised bytes.
    def old_shape(record)
      record.to_h {|key, value|
        case key
        when 'projects' then ['project', with_integer_taxonomy_id(value.first)]
        when 'samples'  then [key, value.map { with_integer_taxonomy_id(it) }]
        else                 [key, value]
        end
      }
    end

    def stringify_taxonomy_id!(organism)
      organism['taxonomy_id'] = organism['taxonomy_id'].to_s if organism&.[]('taxonomy_id').is_a?(Integer)
    end

    def objectify_locus_tag_prefixes!(project)
      return unless project['locus_tag_prefix']

      project['locus_tag_prefix'] = project['locus_tag_prefix'].map { it.is_a?(String) ? {'prefix' => it} : it }
    end

    # A record whose target.data_types holds values outside the Objectives
    # vocabulary, and which has no project_data_type attributes, was
    # converted before the two were told apart: those values are the
    # ProjectDataTypeSet's.
    def separate_project_data_types!(project)
      target     = project['target'] or return
      data_types = target['data_types'] or return
      attributes = Array(project['attributes'])

      return if attributes.any? { it['name'] == 'project_data_type' }

      objectives, project_data_types = data_types.partition { OBJECTIVE_DATA_TYPES.include?(it) }
      return if project_data_types.empty?

      if objectives.empty?
        target.delete('data_types')
      else
        target['data_types'] = objectives
      end

      project['attributes'] = attributes + project_data_types.map { {'name' => 'project_data_type', 'value' => it} }
    end

    # The converters dropped a taxonomy_id that did not read as an integer,
    # and the organism with it when nothing else was left.
    def with_integer_taxonomy_id(holder)
      organism = holder['organism'] or return holder

      old = {
        'taxonomy_id' => Integer(organism['taxonomy_id'].to_s, 10, exception: false),
        'name'        => organism['name']
      }.compact.presence

      holder.to_h {|key, value| [key, key == 'organism' ? old : value] }.compact
    end
  end
end
