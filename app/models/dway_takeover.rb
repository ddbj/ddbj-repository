# That D-way has handed over to this system: from then on nothing is
# registered or curated there. Recorded once, for every database together —
# two places taking registrations would drift apart whatever else were
# done, so the switch is made at one moment.
#
# Until it is, D-way is where status lives: its batches release data, and
# the import brings what it says back over anything set here. From it:
#
# - the hold date releases data here (HoldDateRelease), and a published
#   DRA submission takes its projects and samples along (DRA::LinkedRelease);
# - the import from D-way stops (DataMigration::DwayDefaults.enabled?);
# - an imported DRA submission's status is set here like any other.
#
# DRA's accession numbers are taken over on their own (dra:take_over_numbering),
# since issuing waits only for that.
class DwayTakeover < ApplicationRecord
  def self.done? = exists?

  def self.record!(by:) = create!(taken_over_at: Time.current, taken_over_by: by)
end
