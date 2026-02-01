module FeatureChecker
  BOOLEAN_QUALIFIERS = %w[
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
  ].to_set

  module_function

  def defined_feature?(key)
    defined_features.include?(key.to_s)
  end

  def defined_qualifier?(key)
    defined_qualifiers.include?(key.to_s)
  end

  def qualifier_value_presence_valid?(key, value)
    BOOLEAN_QUALIFIERS.include?(key.to_s) ? value.blank? : value.present?
  end

  def defined_features
    @defined_features ||= Rails.root.join('data/feat.list').readlines(chomp: true).to_set
  end

  def defined_qualifiers
    @defined_qualifiers ||= Rails.root.join('data/qual.list').readlines(chomp: true).to_set
  end
end
