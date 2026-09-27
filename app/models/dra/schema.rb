# What the v3 schema (DDBJRecord::V3::SCHEMA) says is at a place of the SRA
# mapping: the JSON type of its value, so the converter can write `"true"` as
# true and `"36"` as 36 where the spec types them.
module DRA::Schema
  module_function

  # The JSON type at `place` (a DRA::Mapping::Place): the value's, or with
  # `element: true` the type of the elements of the list it ends in.
  def type_at(place, element: false)
    node = place.segments.reduce(root) {|schema, segment|
      field = resolve(schema).fetch('properties').fetch(segment.name) { raise KeyError, "#{place}: the schema has no #{segment.name}" }
      field = resolve(field)
      field = resolve(field.fetch('items'))                if segment.list && !(element && segment.equal?(place.segments.last))
      field = resolve(field.fetch('additionalProperties')) if segment.key
      field
    }

    node = resolve(node.fetch('items')) if element

    node['type'] || ('object' if node.key?('properties'))
  end

  def root = DDBJRecord::V3::SCHEMA

  # A $ref followed, and `anyOf: [X, null]` taken as X.
  def resolve(schema)
    schema = root.dig('$defs', schema['$ref'].delete_prefix('#/$defs/')) if schema['$ref']
    schema = resolve(schema['anyOf'].find { it['type'] != 'null' }) if schema['anyOf']
    schema
  end
end
