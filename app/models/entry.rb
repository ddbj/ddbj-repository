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

  # What a curator may set an entry to. Not the whole nine-state enum:
  # `submission_accepted`, `curating` and `accession_issued` describe how
  # far the submission got and are written by the pipeline, so offering
  # them would report a successful bulk update that changed nothing a
  # curator can see. The two that do something today are `canceled` and
  # `withdrawn`, which take the entry out of the flatfile.
  SETTABLE_STATUSES = %w[public private temporarily_suppressed permanently_suppressed canceled withdrawn].freeze
end
