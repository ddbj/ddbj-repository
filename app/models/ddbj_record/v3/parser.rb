# frozen_string_literal: true

module DDBJRecord
  module V3
    # Builds a DDBJRecord::V3::Root from JSON by following the schema: an
    # object of a model becomes that model's Data class, a list is built
    # element by element, a dict value by value, and anything else is kept
    # as it is.
    #
    # What the spec would not read is refused, as TypeError: a key the model
    # does not have (every model but Provenance forbids extra keys), and a
    # container of the wrong kind (`"sequences": []` where a model is
    # expected).
    #
    # Full-document parse via Oj; nothing reads a v3 record this way that
    # could not hold it in memory.
    module Parser
      REF_PREFIX = '#/$defs/'

      # How to build each model, worked out once from the schema: its class,
      # whether it takes keys it does not declare, and per field the member,
      # the JSON key and the schema of the value.
      Plan = Data.define(:klass, :open, :fields)

      def self.parse(io)
        raw = io.respond_to?(:read) ? io.read : io.to_s

        model(Oj.load(raw, mode: :strict), 'Root')
      end

      def self.model(value, name)
        plan = PLANS.fetch(name)
        hash = dict(value)

        unless plan.open || (extra = hash.keys - plan.fields.keys).empty?
          raise TypeError, "#{name} has no field #{extra.join(', ')}"
        end

        plan.klass.new(**plan.fields.to_h {|key, (member, schema)| [member, build(hash[key], schema)] })
      end

      def self.build(value, schema)
        return nil if value.nil?

        if (ref = schema['$ref'])
          model(value, ref.delete_prefix(REF_PREFIX))
        else
          case schema['type']
          when 'array'  then list(value).map { build(it, schema.fetch('items', {})) }
          when 'object' then dict(value).transform_values { build(it, schema.fetch('additionalProperties', {})) }
          else value
          end
        end
      end

      def self.list(value)
        value.is_a?(Array) ? value : raise(TypeError, "expected a list, got #{value.class}")
      end

      def self.dict(value)
        value.is_a?(Hash) ? value : raise(TypeError, "expected an object, got #{value.class}")
      end

      # A field that may be null is `anyOf: [<schema>, {type: null}]`; the
      # value, when there is one, is read by the other. A union of two
      # non-null schemas would need the value to pick between them, which
      # nothing here does — so one appearing in the spec stops the load
      # rather than being read as its first branch.
      def self.non_null(schema)
        options = schema['anyOf'] or return schema
        others  = options.reject { it['type'] == 'null' }

        raise ArgumentError, "a union of #{others.size} schemas is not supported: #{schema}" unless others.one?

        non_null(others.first)
      end

      def self.resolve(schema)
        schema = non_null(schema)

        schema = schema.merge('items' => resolve(schema['items']))                               if schema['items'].is_a?(Hash)
        schema = schema.merge('additionalProperties' => resolve(schema['additionalProperties'])) if schema['additionalProperties'].is_a?(Hash)

        schema
      end

      PLANS = MODELS.to_h {|name, model|
        fields = model.fetch('properties').to_h {|key, schema| [key, [key.to_sym, resolve(schema)]] }

        [name, Plan.new(klass: V3.const_get(name), open: model['additionalProperties'] != false, fields:)]
      }.freeze

      private_class_method :build, :list, :dict, :non_null, :resolve
    end
  end
end
