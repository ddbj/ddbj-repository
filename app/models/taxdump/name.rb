class Taxdump::Name < Taxdump::Record
  def self.scientific_names(tax_ids)
    where(
      tax_id:     tax_ids,
      name_class: 'scientific name'
    ).group_by(&:tax_id).transform_values {|names|
      names.one? ? names.first.name_txt : nil
    }
  end

  def self.common_names(tax_ids)
    where(
      tax_id:     tax_ids,
      name_class: 'common name'
    ).group_by(&:tax_id).transform_values {|names|
      names.one? ? names.first.name_txt : nil
    }
  end
end
