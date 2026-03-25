# frozen_string_literal: true

module Flatfile
  # Entry-by-entry flatfile renderer for large files.
  #
  # Unlike Root, which loads all entries into memory at once,
  # StreamingRenderer processes one entry at a time and writes
  # output incrementally to the given IO.
  #
  #   renderer = Flatfile::StreamingRenderer.new(record, features_by_sequence_id, io)
  #
  #   entries.each do |raw_entry|
  #     renderer.render_entry(raw_entry)
  #   end
  class StreamingRenderer
    TEMPLATE = Root::TEMPLATE

    def initialize(record, features_by_sequence_id, io)
      @record                  = record
      @features_by_sequence_id = features_by_sequence_id
      @io                      = io
      @tax_cache               = TaxIdCache.new
      @entries                 = []
    end

    attr_reader :record, :entries

    def render_entry(raw_entry)
      flatfile_entry = build_flatfile_entry(raw_entry)

      @entries = [flatfile_entry]

      io = @io

      Context.new(self).instance_eval {
        __buf__ = Buffer.new(io)

        eval TEMPLATE.src, binding

        __buf__.flush
      }
    end

    private

    def build_flatfile_entry(raw_entry)
      Entry.new(raw_entry,
        root:            self,
        features:        @features_by_sequence_id[raw_entry.id] || [],
        scientific_name: @tax_cache.scientific_name(raw_entry.tax_id),
        common_name:     @tax_cache.common_name(raw_entry.tax_id),
        ancestor_names:  @tax_cache.ancestor_names(raw_entry.tax_id)
      )
    end
  end
end
