# frozen_string_literal: true

module DDBJRecord
  module V3
    # Builds a DDBJRecord::V3::Root from JSON by following the schema: an
    # object of a model becomes that model's Data class (keys the model does
    # not have are ignored), a list is built element by element, a dict value
    # by value, and anything else is kept as it is. A value whose container
    # is not the one the schema says (`"sequences": []` where a model is
    # expected) raises TypeError.
    #
    # Full-document parse via Oj; nothing reads a v3 record this way that
    # could not hold it in memory.
    module Parser
      REF_PREFIX = '#/$defs/'

      def self.parse(io)
        raw = io.respond_to?(:read) ? io.read : io.to_s

        model(Oj.load(raw, mode: :strict), 'Root')
      end

      def self.build(value, schema)
        return nil if value.nil?

        if (ref = schema['$ref'])
          model(value, ref.delete_prefix(REF_PREFIX))
        elsif (options = schema['anyOf'])
          build(value, options.find { it['type'] != 'null' })
        else
          case schema['type']
          when 'array'  then list(value).map { build(it, schema.fetch('items', {})) }
          when 'object' then dict(value).transform_values { build(it, schema.fetch('additionalProperties', {})) }
          else value
          end
        end
      end

      def self.model(value, name)
        properties = MODELS.fetch(name).fetch('properties')
        hash       = dict(value)

        V3.const_get(name).new(**properties.to_h {|field, schema| [field.to_sym, build(hash[field], schema)] })
      end

      def self.list(value)
        value.is_a?(Array) ? value : raise(TypeError, "expected a list, got #{value.class}")
      end

      def self.dict(value)
        value.is_a?(Hash) ? value : raise(TypeError, "expected an object, got #{value.class}")
      end
    end
  end
end
