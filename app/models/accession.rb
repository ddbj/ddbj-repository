class Accession < ApplicationRecord
  belongs_to :submission

  has_many :histories, dependent: :destroy, class_name: 'AccessionHistory'
end
