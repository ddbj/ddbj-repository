require 'rails_helper'

RSpec.describe Sequence, type: :model do
  example do
    expect(Sequence.allocate!(:jpo_na, count: 1).last).to eq('QP000001')

    Sequence.find_by!(scope: 'jpo_na').update! next: 1000000

    expect(Sequence.allocate!(:jpo_na, count: 1).last).to eq('QQ000001')
  end
end
