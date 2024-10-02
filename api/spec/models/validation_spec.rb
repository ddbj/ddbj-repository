require "rails_helper"

RSpec.describe Validation, type: :model do
  describe ".validity" do
    let!(:valid) { create(:validation, validity: "valid") }

    let!(:invalid) {
      create(:validation, validity: "invalid") { |validation|
        create :obj, validation:, validity: "valid"
        create :obj, validation:, validity: nil
      }
    }

    let!(:error) {
      create(:validation, validity: "error") { |validation|
        create :obj, validation:, validity: "valid"
        create :obj, validation:, validity: "invalid"
        create :obj, validation:, validity: nil
      }
    }

    let!(:null) { create(:validation, validity: nil) }

    example do
      expect(Validation.validity("valid")).to contain_exactly(valid)
      expect(Validation.validity("invalid")).to contain_exactly(invalid)
      expect(Validation.validity("error")).to contain_exactly(error)
      expect(Validation.validity("null")).to contain_exactly(null)

      expect(Validation.validity("valid", "invalid")).to contain_exactly(valid, invalid)
      expect(Validation.validity("invalid", "error")).to contain_exactly(invalid, error)
      expect(Validation.validity("error", "null")).to contain_exactly(error, null)
    end
  end
end
