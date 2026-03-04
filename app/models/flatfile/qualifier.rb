# frozen_string_literal: true

module Flatfile
  Qualifier = Data.define(:key, :value) {
    KEYS = Rails.root.join('data/qual.list').readlines(chomp: true).to_set.freeze

    BOOLEAN_KEYS = %w[
      circular_RNA
      environmental_sample
      focus
      germline
      macronuclear
      proviral
      pseudo
      rearranged
      ribosomal_slippage
      trans_splicing
      transgenic
    ].to_set.freeze

    NEED_QUOTE_KEYS = Rails.root.join('data/kq_note.lst').readlines.filter_map {|line|
      key, format = line.split("\t").values_at(0, 3)

      format == %(ff:"{0}") ? key : false
    }.to_set.freeze

    def valid?
      return false unless KEYS.include?(key)

      BOOLEAN_KEYS.include?(key) == value.nil?
    end

    def need_quote?
      NEED_QUOTE_KEYS.include?(key)
    end
  }
end
