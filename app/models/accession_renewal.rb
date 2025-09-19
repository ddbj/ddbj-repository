class AccessionRenewal < ApplicationRecord
  belongs_to :accession, inverse_of: :renewals

  has_many :validation_details, dependent: :destroy, class_name: 'AccessionRenewalValidationDetail', inverse_of: :renewal

  has_one_attached :file

  enum :progress, %w[waiting running finished canceled].index_by(&:to_sym)
  enum :validity, %w[valid invalid error].index_by(&:to_sym), prefix: true
end
