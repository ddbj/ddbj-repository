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
        Feature.new(
          entry:      self,
          type:       'source',
          location:   entry[:location],
          qualifiers: entry[:source_qualifiers]
        ),
        *features.map {|feature|
          Feature.new(
            entry:      self,
            type:       feature[:type],
            location:   feature[:location],
            qualifiers: feature[:qualifiers]
          )
        }
      ].sort_by.with_index {|feature, i|
        [*feature.sort_keys, i]
      }
    end

    attr_reader :entry, :root, :features, :scientific_name, :common_name, :ancestor_names

    delegate :[], :dig, to: :entry

    def na? = mol_type != 'protein'
    def aa? = mol_type == 'protein'

    def mol_type
      @mol_type ||= qualifier_value(entry[:source_qualifiers], :mol_type)
    end

    def seqid
      @seqid ||= Seqid.new(*entry[:id].split('|').drop(1))
    end

    def source
      if scientific_name && common_name
        "#{scientific_name} (#{common_name})"
      else
        scientific_name || 'unidentified'
      end
    end

    def location_span
      Bio::Locations.new(entry[:location]).span.uniq
    end

    def invention_title
      if title = root.dig(:submission, :invention_title).presence
        title
      else
        "Patent application sequence for #{Helper.format_seqid(seqid)}"
      end
    end

    def organism
      entry.dig(:source_qualifiers, :organism).first[:value]
    end

    def source_feature
      @source_feature ||= features.find(&:source?)
    end

    def qualifier_value(quals, key)
      return nil unless vals = quals[key]

      vals.first&.then { it[:value] }
    end

    def base_count
      h = entry[:sequence].chars.tally

      %w[a c g t].to_h { [it, h[it] || 0] }
    end

    def sequence
      @sequence ||= na? ? entry[:sequence] : entry[:sequence].upcase
    end
  end
end
