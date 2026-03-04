RSpec.configure do |config|
  config.include Module.new {
    extend ActiveSupport::Concern

    included do
      set_fixture_class names: Taxdump::Name, nodes: Taxdump::Node
    end
  }
end
