# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # Singleton wrapper around schema/canon/array-modes.yml.
    module Registry
      PATH = Rails.root.join('schema/canon/array-modes.yml').freeze

      class << self
        def canonical_version
          load!.fetch('canonical_version')
        end

        def arrays         = load!.fetch('arrays')
        def volatile_paths = load!.fetch('volatile_paths')
        def strings        = load!.fetch('strings')
        def floats         = load!.fetch('floats', [])

        def reload!
          @data = nil
        end

        private

        def load!
          @data ||= YAML.safe_load_file(PATH, permitted_classes: [Symbol]).freeze
        end
      end
    end
  end
end
