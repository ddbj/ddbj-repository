# DDBJ Record schema v3.
#
# The types are the spec's, not a copy of it: vendor/ddbj-record-specifications
# (the gitlink pins the revision) generates schema/ddbj-record/v3.schema.json,
# and one Data class is defined here per model in it — `Root` for the record,
# and one per `$defs` entry, named after it, whose members are the model's
# fields. Moving the submodule means regenerating the schema with the spec's
# locked toolchain (the Canon workflow does the same and fails on a
# difference):
#
#   uv run --frozen --project vendor/ddbj-record-specifications \
#     python -m ddbj_record.schema.cli --version v3 > schema/ddbj-record/v3.schema.json
#
# and re-deriving schema/canon/array-modes.yml, whose header cites the
# revision (spec_pin_test).
#
# Two members shadow methods every Data has: `ProjectTarget#method` and
# `Pool#members`. Code that walks a record generically has to reach for
# `to_h` rather than `members`. And the models are constants of this module
# (`File`, `Sample`, …), so code inside it names Ruby's own with `::File`.
module DDBJRecord
  module V3
    SCHEMA = JSON.parse(Rails.root.join('schema/ddbj-record/v3.schema.json').read).freeze

    # The models of the schema by name (`Root` for the record itself).
    MODELS = SCHEMA.fetch('$defs').merge('Root' => SCHEMA).select {|_, model| model['type'] == 'object' && model.key?('properties') }.freeze

    MODELS.each do |name, model|
      const_set name, Data.define(*model.fetch('properties').keys.map(&:to_sym))
    end
  end
end
