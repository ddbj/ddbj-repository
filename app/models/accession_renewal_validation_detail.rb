class AccessionRenewalValidationDetail < ApplicationRecord
  belongs_to :renewal, class_name: 'AccessionRenewal'
end
