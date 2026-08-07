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

  # What a curator may set an entry to: everything except
  # `submission_accepted`, which is false of every entry there is — an
  # entry is created with its accession, so it has never been in the
  # state of being accepted and not yet numbered.
  #
  # `accession_issued` is in the list because it is the way back.
  # Withdrawing an entry keeps it out of the flatfile, and a curator who
  # did that in error has to be able to undo it — leaving the state an
  # entry starts in off the list made retraction one-way, which is not
  # something a screen should do quietly.
  SETTABLE_STATUSES = (Lifecycleable::STATUSES.keys - %w[submission_accepted]).freeze
end
