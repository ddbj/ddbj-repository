# frozen_string_literal: true

module Flatfile
  class Entry
    Seqid = Data.define(
      :country_code,
      :document_number,
      :kind_code,
      :sequence_number
    )

    def initialize(entry, root:, features:, scientific_name:, common_name:, ancestor_names:)
      @entry           = entry
      @root            = root
      @scientific_name = scientific_name
      @common_name     = common_name
      @ancestor_names  = ancestor_names

      @features = [
        *entry.source_features.map {|sf|
          quals = (sf.source&.qualifiers || {}).dup

          if sf.source&.organism
            quals['organism'] ||= [DDBJRecord::Qualifier.new(id: nil, value: sf.source.organism)]
          end

          if sf.source&.mol_type
            quals['mol_type'] ||= [DDBJRecord::Qualifier.new(id: nil, value: sf.source.mol_type)]
          end

          Feature.new(
            entry:      self,
            type:       'source',
            location:   sf.location,
            qualifiers: quals
          )
        },

        *features.map {|feature|
          Feature.new(
            entry:      self,
            type:       feature.type,
            location:   feature.location,
            qualifiers: feature.qualifiers
          )
        }
      ].sort_by.with_index {|feature, i|
        [*feature.sort_keys, i]
      }
    end

    attr_reader :entry, :root, :features, :scientific_name, :common_name, :ancestor_names

    delegate_missing_to :entry

    def na? = mol_type != 'protein'
    def aa? = mol_type == 'protein'

    def mol_type
      @mol_type ||= raw_primary_source_feature&.source&.mol_type
    end

    def seqid
      @seqid ||= Seqid.new(*entry.id.split('|').drop(1))
    end

    def source
      if scientific_name && common_name
        "#{scientific_name} (#{common_name})"
      else
        scientific_name || 'unidentified'
      end
    end

    def location_span
      Bio::Locations.new(raw_primary_source_feature.location).span.uniq
    end

    def invention_title
      if title = root.record.submission&.invention_title.presence
        title
      else
        "Patent application sequence for #{Helper.format_seqid(seqid)}"
      end
    end

    def organism
      raw_primary_source_feature&.source&.organism || 'unidentified'
    end

    def primary_source_feature
      @primary_source_feature ||= features.find {|f|
        f.source? && f.location == raw_primary_source_feature&.location
      } || features.find(&:source?)
    end

    def base_count
      h = Hash.new(0)
      entry.sequence.each_char {|c| h[c] += 1 }

      %w[a c g t].to_h { [it, h[it]] }
    end

    def sequence
      @sequence ||= na? ? entry.sequence : entry.sequence.upcase
    end

    private

    def raw_primary_source_feature
      @raw_primary_source_feature ||= entry.source_features.find { it.source&.mol_type } || entry.source_features.first
    end
  end
end
