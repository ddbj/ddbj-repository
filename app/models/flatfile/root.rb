# frozen_string_literal: true

module Flatfile
  class Root
    TEMPLATE = Erubi::Engine.new(Rails.root.join('app/models/flatfile/template.erb').read, bufval: '__buf__')

    def initialize(record, entries)
      features_by_sequence_id    = record.features.group_by(&:sequence_id)
      tax_ids                    = entries.map(&:tax_id).uniq
      scientific_names_by_tax_id = Taxdump::Name.scientific_names(tax_ids)
      common_names_by_tax_id     = Taxdump::Name.common_names(tax_ids)
      ancestor_names_by_tax_id   = Taxdump::Node.ancestor_names(tax_ids)

      @record = record

      @entries = entries.map {|entry|
        tax_id = entry.tax_id

        Entry.new(entry,
          root:            self,
          features:        features_by_sequence_id[entry.id] || [],
          scientific_name: scientific_names_by_tax_id[tax_id],
          common_name:     common_names_by_tax_id[tax_id],
          ancestor_names:  ancestor_names_by_tax_id[tax_id] || []
        )
      }
    end

    attr_reader :record, :entries

    def render
      file = Tempfile.open(['flatfile', '.flat'])
      file.binmode

      Context.new(self).instance_eval do
        __buf__ = Buffer.new(file)

        eval TEMPLATE.src, binding

        __buf__.flush
      end

      file.rewind
      file
    end
  end
end
