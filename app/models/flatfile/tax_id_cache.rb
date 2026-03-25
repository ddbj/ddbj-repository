# frozen_string_literal: true

module Flatfile
  # Lazy-loading cache for Taxdump lookups.
  #
  # Instead of bulk-loading all tax_ids upfront (as Root does),
  # this cache queries on demand and caches results. For genome
  # assemblies with a single organism, only one query per lookup
  # type is needed.
  class TaxIdCache
    def initialize
      @scientific_names = {}
      @common_names     = {}
      @ancestor_names   = {}
      @loaded           = Set.new
    end

    def scientific_name(tax_id)
      ensure_loaded(tax_id)

      @scientific_names[tax_id]
    end

    def common_name(tax_id)
      ensure_loaded(tax_id)

      @common_names[tax_id]
    end

    def ancestor_names(tax_id)
      ensure_loaded(tax_id)

      @ancestor_names[tax_id] || []
    end

    private

    def ensure_loaded(tax_id)
      return if tax_id.nil? || @loaded.include?(tax_id)

      ids = [tax_id]

      @scientific_names.merge! Taxdump::Name.scientific_names(ids)
      @common_names.merge!     Taxdump::Name.common_names(ids)
      @ancestor_names.merge!   Taxdump::Node.ancestor_names(ids)

      @loaded.add tax_id
    end
  end
end
