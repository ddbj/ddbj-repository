class AddSourceChecksumToSubmissions < ActiveRecord::Migration[8.1]
  # "Has the D-way source changed since the last import?" — asked once per
  # submission per run, over a corpus of ~10K.
  #
  # It used to be answered by comparing the converter output against the
  # bytes in the materialised-record cache blob. That only worked while the
  # two were the same thing; now that the chain stores the *canonical* form
  # (so diff indices line up with what apply mutates), the raw output no
  # longer matches the cache, and re-deriving the canonical form just to
  # compare would cost a canonicalisation pass per submission — seconds
  # each, on every run, including the ~99% that changed nothing.
  #
  # So the question gets its own answer: a checksum of the raw converter
  # output. It also says what it means, which the blob comparison did not —
  # this is "unchanged at the source", deliberately not "unchanged in the
  # chain", so curator edits made between imports survive an idempotent
  # re-run.
  def change
    add_column :submissions, :source_checksum, :string
  end
end
