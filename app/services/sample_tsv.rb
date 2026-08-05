# Shared constants for the SampleTSV exporter ↔ importer round trip.
# The two services agree on the leading reserved columns (identifier
# first, then read-only context, then editable typed cols) so a name
# collision with an arbitrary v3 attribute can be filtered on both
# sides from one place.
module SampleTSV
  IDENTIFIER_COL  = 'sample_name'
  READ_ONLY_COLS  = %w[accession].freeze
  TYPED_COLS      = %w[status].freeze
  COLUMNS         = ([IDENTIFIER_COL] + READ_ONLY_COLS + TYPED_COLS).freeze

  # Why a row was rejected. Added to the error report so the curator can
  # read the reason next to the row, and stripped on the way back in —
  # fixing the file and re-uploading it is the documented loop, and an
  # unrecognised header is read as an attribute name, so without this the
  # stale error message would be written into the record as `error`.
  ERROR_COL = 'error'

  # Columns this file format used to emit. Same trap: a column merely
  # deleted from COLUMNS does not go away, it comes back as sample data.
  # A spreadsheet downloaded before assignment moved to the request would
  # otherwise write `assignee_uid` into every sample's attribute bag and
  # commit that to the patch chain — a corrupted record produced by
  # following the documented download-edit-upload loop.
  RETIRED_COLS = %w[assignee_uid].freeze

  # Header names that are never sample attributes, whatever they are.
  RESERVED_COLS = (COLUMNS + RETIRED_COLS + [ERROR_COL]).freeze
end
