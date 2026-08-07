# One entry of an ST.26 submission, and the accession number issued for
# it. Every row belongs to an st26 submission — BioProject and BioSample
# carry their accessions on their own rows — which is why the table is
# named after the entry rather than after the number.
#
# `entry_id` is the entry's own identifier, the word `validation_details`
# and DDBJRecordValidator already use. `number` is the accession.
class Entry < ApplicationRecord
  include Lifecycleable

  belongs_to :submission

  has_many :histories, dependent: :destroy, class_name: 'EntryHistory'
end
