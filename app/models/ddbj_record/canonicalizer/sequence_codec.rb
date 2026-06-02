# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # `/sequences/entries/*/sequence` is carved out from the multi-line class
    # in §2.2 because the data can run into the multi-GB range and NFC over
    # pure ASCII would be a wasted full materialization. The streaming
    # production path emits canonical bytes directly to the serializer; this
    # in-memory codec is used by tests and for sub-MB sequences where loading
    # is acceptable.
    module SequenceCodec
      ALLOWED       = /\A[acgtn]*\z/.freeze
      WS_TO_STRIP   = /[\t\n\r ]/.freeze

      module_function

      def normalize(string)
        s = string.encode(Encoding::UTF_8).b.gsub(WS_TO_STRIP, '').downcase

        unless s.match?(ALLOWED)
          raise SequenceAlphabetError, 'sequence contains a character outside [acgtn]'
        end

        s
      end
    end
  end
end
