class Accession < ApplicationRecord
  belongs_to :submission

  has_many :renewals, dependent: :destroy, class_name: 'AccessionRenewal'
end
