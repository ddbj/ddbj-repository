# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # §2.3 numeric guard.
    #
    # Integers must sit in IEEE-754 double-safe range so cross-runtime
    # decoders never lose precision.
    #
    # Floats are rejected outright. The current v3 schema carries no
    # numerically-typed scientific attributes; any future float field must
    # opt in by passing `allow_float: true`, which lifts the guard for that
    # subtree.
    module NumberGuard
      SAFE_MAX = (2**53) - 1
      SAFE_MIN = -SAFE_MAX

      module_function

      def check!(value, pointer:, allow_float: false)
        case value
        when Integer
          unless value.between?(SAFE_MIN, SAFE_MAX)
            raise IntegerOutOfRangeError, "integer at #{pointer} outside IEEE-754 safe range: #{value}"
          end
        when Float
          unless allow_float
            raise FloatNotAllowedError, "float at #{pointer} is not allowed by canonical v1; tag the schema path to opt in"
          end

          if value.nan? || value.infinite?
            raise UnsupportedValueError, "non-finite float at #{pointer}: #{value}"
          end

          # -0.0 → 0.0 per §2.3
          return 0.0 if value.zero?
        end

        value
      end
    end
  end
end
