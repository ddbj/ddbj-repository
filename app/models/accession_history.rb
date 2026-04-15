class AccessionHistory < ApplicationRecord
  belongs_to :accession
  belongs_to :user
end
