# DDBJ Record schema v3.
#
# The types are the spec's, not a copy of it: vendor/ddbj-record-specifications
# (the gitlink pins the revision) generates schema/ddbj-record/v3.schema.json,
# and one Data class is defined here per model in it — `Root` for the record,
# and one per `$defs` entry, named after it, whose members are the model's
# fields. The Canon workflow regenerates the schema from the submodule and
# fails if it differs, so moving the submodule means regenerating the schema:
#
#   PYTHONPATH=vendor/ddbj-record-specifications python -m ddbj_record.schema.cli --version v3 \
#     > schema/ddbj-record/v3.schema.json
#
# and updating SPEC_SHA.
module DDBJRecord
  module V3
    SCHEMA_VERSION_PREFIX = 'v3'.freeze
    SPEC_SHA              = '47cd4433123652d6355e06a2678e96fc34c04caf'.freeze

    SCHEMA = JSON.parse(Rails.root.join('schema/ddbj-record/v3.schema.json').read).freeze

    # The models of the schema by name (`Root` for the record itself).
    MODELS = SCHEMA.fetch('$defs').merge('Root' => SCHEMA).select {|_, model| model['type'] == 'object' && model.key?('properties') }.freeze

    MODELS.each do |name, model|
      const_set name, Data.define(*model.fetch('properties').keys.map(&:to_sym))
    end
  end
end
