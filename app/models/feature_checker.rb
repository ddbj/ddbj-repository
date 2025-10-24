module FeatureChecker
  BOOLEAN_QUALIFIERS = Set.new(%w[
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
  ])

  module_function

  def defined_feature?(key)
    defined_features.include?(key)
  end

  def defined_qualifier?(key)
    defined_qualifiers.include?(key)
  end

  def qualifier_value_presence_valid?(key, value)
    BOOLEAN_QUALIFIERS.include?(key) ? value.blank? : value.present?
  end

  def defined_features
    @defined_features ||= Set.new(Rails.root.join('data/feat.list').readlines(chomp: true))
  end

  def defined_qualifiers
    @defined_qualifiers ||= Set.new(Rails.root.join('data/qual.list').readlines(chomp: true))
  end
end
