# DDBJ Record schema v3.
#
# Backed by vendor/ddbj-record-specifications (submodule, pinned to
# bdcdb8d8 / 2026-04-13). When the spec moves, run
# `git submodule update --remote vendor/ddbj-record-specifications`,
# regenerate schema/canon/v3-fields.yml, and bump CHANGELOG.
module DDBJRecord
  module V3
    SCHEMA_VERSION_PREFIX = 'v3'.freeze
    SPEC_SHA              = 'bdcdb8d8c83ccf0945e2a07ecc1de57614bfab42'.freeze
  end
end
