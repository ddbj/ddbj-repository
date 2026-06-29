# Shared constants for the SampleTSV exporter ↔ importer round trip.
# The two services agree on the leading reserved columns (identifier
# first, then read-only context, then editable typed cols) so a name
# collision with an arbitrary v3 attribute can be filtered on both
# sides from one place.
module SampleTSV
  IDENTIFIER_COL  = 'sample_name'
  READ_ONLY_COLS  = %w[accession].freeze
  TYPED_COLS      = %w[status assignee_uid].freeze
  COLUMNS         = ([IDENTIFIER_COL] + READ_ONLY_COLS + TYPED_COLS).freeze
end
