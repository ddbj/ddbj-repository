require 'rails_helper'

RSpec.describe Flatfile::TaxIdCache do
  subject(:cache) { described_class.new }

  before do
    allow(Taxdump::Name).to receive(:scientific_names).and_return({})
    allow(Taxdump::Name).to receive(:common_names).and_return({})
    allow(Taxdump::Node).to receive(:ancestor_names).and_return({})
  end

  describe '#scientific_name' do
    it 'queries Taxdump and caches the result' do
      allow(Taxdump::Name).to receive(:scientific_names).with([9606]).and_return(9606 => 'Homo sapiens')

      expect(cache.scientific_name(9606)).to eq('Homo sapiens')
      expect(cache.scientific_name(9606)).to eq('Homo sapiens')

      expect(Taxdump::Name).to have_received(:scientific_names).with([9606]).once
    end
  end

  describe '#common_name' do
    it 'queries Taxdump and caches the result' do
      allow(Taxdump::Name).to receive(:common_names).with([9606]).and_return(9606 => 'human')

      expect(cache.common_name(9606)).to eq('human')
    end
  end

  describe '#ancestor_names' do
    it 'returns ancestor names' do
      allow(Taxdump::Node).to receive(:ancestor_names).with([9606]).and_return(9606 => %w[Eukaryota Metazoa])

      expect(cache.ancestor_names(9606)).to eq(%w[Eukaryota Metazoa])
    end

    it 'returns empty array for unknown tax_id' do
      expect(cache.ancestor_names(99999)).to eq([])
    end
  end

  it 'does not query for nil tax_id' do
    cache.scientific_name(nil)

    expect(Taxdump::Name).not_to have_received(:scientific_names)
  end

  it 'queries once for multiple lookups on the same tax_id' do
    allow(Taxdump::Name).to receive(:scientific_names).with([9606]).and_return(9606 => 'Homo sapiens')
    allow(Taxdump::Name).to receive(:common_names).with([9606]).and_return(9606 => 'human')
    allow(Taxdump::Node).to receive(:ancestor_names).with([9606]).and_return(9606 => %w[Eukaryota])

    cache.scientific_name(9606)
    cache.common_name(9606)
    cache.ancestor_names(9606)

    expect(Taxdump::Name).to have_received(:scientific_names).once
    expect(Taxdump::Name).to have_received(:common_names).once
    expect(Taxdump::Node).to have_received(:ancestor_names).once
  end
end
