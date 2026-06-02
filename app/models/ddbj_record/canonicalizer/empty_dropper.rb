# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # §2.5 — `null`, `""`, `[]`, `{}` are dropped from their parent. `0` and
    # `false` are NOT empty. The rule is applied at object-key level; the
    # array variant lives in ArraySorter (only keyed / bag drop empties;
    # ordered arrays hard-reject because removal would shift indices).
    module EmptyDropper
      module_function

      def empty?(value)
        case value
        when nil          then true
        when ''           then true
        when Array, Hash  then value.empty?
        else                   false
        end
      end
    end
  end
end
