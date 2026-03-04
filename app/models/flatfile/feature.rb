# frozen_string_literal: true

module Flatfile
  class Feature
    SORT_ORDER = %w[
      conflict
      unsure
      variation
      source
      CDS
      exon
      intron
      mRNA
      ncRNA
      rRNA
      tRNA
      tmRNA
      prim_transcript
      precursor_RNA
      repeat_region
      D-loop
      rep_origin
      promoter
      protein_bind
      primer_bind
      RBS
      transit_peptide
      sig_peptide
      mat_peptide
      3'UTR
      5'UTR
      -10_signal
      -35_signal
      CAAT_signal
      GC_signal
      LTR
      TATA_signal
      terminator
      attenuator
      enhancer
      polyA_signal
      polyA_site
      C_region
      D_segment
      J_segment
      N_region
      S_region
      V_region
      V_segment
      misc_binding
      misc_difference
      misc_feature
      misc_recomb
      misc_RNA
      misc_signal
      misc_structure
      iDNA
      modified_base
      stem_loop
      STS
      Operon
      oriT
      gap
    ].each_with_index.to_h

    def initialize(entry:, type:, location:, qualifiers:)
      @entry    = entry
      @type     = type
      @location = location

      @qualifiers = qualifiers.flat_map {|k, vs|
        if type == 'source' && k == 'mol_type' && entry.aa?
          []
        elsif k == 'organism'
          [Qualifier.new('organism', entry.scientific_name || 'unidentified')]
        else
          vs.map { Qualifier.new(k, it.value) }
        end
      }

      @qualifiers << Qualifier.new('db_xref', "taxon:#{entry.tax_id}") if type == 'source'
    end

    attr_reader :entry, :type, :location, :qualifiers

    def source? = type == 'source'

    def valid_qualifiers
      qualifiers.select(&:valid?)
    end

    def invalid_qualifiers
      qualifiers.reject(&:valid?)
    end

    def sort_keys
      locations = Bio::Locations.new(location)
      first     = locations.first
      last      = locations.last
      from      = first.strand == 1 ? first.from : first.to
      to        = last.strand == 1  ? last.from  : last.to

      [from, -to, SORT_ORDER[type] || Float::INFINITY]
    end
  end
end
