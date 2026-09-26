# frozen_string_literal: true

module DDBJRecord
  # The shape the spec's v3 took at ddbj/ddbj-record-specifications#11, for
  # records the repository wrote before it:
  #
  #   - `project` (one object) became `projects` (a list; a BioProject's
  #     record holds one)
  #   - `taxonomy_id` is the string as written, not an integer
  #
  # and LocusTagPrefix as a bare string, as BioProject::Converter wrote it
  # before it carried the BioSample (2026-08-27). (ProjectDataTypeSet values
  # that converter mixed into `target.data_types` are left: which values they
  # are cannot be told from the record, and PublicXML::Bp::PackageRenderer
  # reads them apart.)
  #
  # `call` puts a stored record into the current shape: Submission reads a
  # chain written under an older ddbj-canon through it, and rake
  # ddbj_record:reshape_v3 rewrites every chain with it. `old_shape` goes
  # the other way for a converter's output, so the importers can still
  # recognise an unchanged source by the checksum taken before the change
  # (Submission#same_source?).
  module ReshapeV3
    module_function

    def call(record)
      record = record.deep_dup

      if record.key?('project')
        raise ArgumentError, 'the record has both project and projects' if record.key?('projects')

        project = record.delete('project')
        record['projects'] = [project] if project.present?
      end

      Array(record['projects']).each do |project|
        stringify_taxonomy_id!(project['organism'])
        objectify_locus_tag_prefixes!(project)
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
