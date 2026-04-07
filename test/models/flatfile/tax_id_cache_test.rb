require 'test_helper'

class Flatfile::TaxIdCacheTest < ActiveSupport::TestCase
  test 'scientific_name queries Taxdump and caches the result' do
    call_count = 0

    Taxdump::Name.stub :scientific_names, ->(_) { call_count += 1; {9606 => 'Homo sapiens'} } do
      Taxdump::Name.stub :common_names, ->(_) { {} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { {} } do
          cache = Flatfile::TaxIdCache.new

          assert_equal 'Homo sapiens', cache.scientific_name(9606)
          assert_equal 'Homo sapiens', cache.scientific_name(9606)
          assert_equal 1, call_count
        end
      end
    end
  end

  test 'common_name queries Taxdump and caches the result' do
    Taxdump::Name.stub :scientific_names, ->(_) { {} } do
      Taxdump::Name.stub :common_names, ->(_) { {9606 => 'human'} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { {} } do
          cache = Flatfile::TaxIdCache.new

          assert_equal 'human', cache.common_name(9606)
        end
      end
    end
  end

  test 'ancestor_names returns ancestor names' do
    Taxdump::Name.stub :scientific_names, ->(_) { {} } do
      Taxdump::Name.stub :common_names, ->(_) { {} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { {9606 => %w[Eukaryota Metazoa]} } do
          cache = Flatfile::TaxIdCache.new

          assert_equal %w[Eukaryota Metazoa], cache.ancestor_names(9606)
        end
      end
    end
  end

  test 'returns empty array for unknown tax_id' do
    Taxdump::Name.stub :scientific_names, ->(_) { {} } do
      Taxdump::Name.stub :common_names, ->(_) { {} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { {} } do
          cache = Flatfile::TaxIdCache.new

          assert_equal [], cache.ancestor_names(99999)
        end
      end
    end
  end

  test 'does not query for nil tax_id' do
    called = false

    Taxdump::Name.stub :scientific_names, ->(_) { called = true; {} } do
      Taxdump::Name.stub :common_names, ->(_) { {} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { {} } do
          cache = Flatfile::TaxIdCache.new
          cache.scientific_name(nil)

          refute called, 'scientific_names should not have been called for nil tax_id'
        end
      end
    end
  end

  test 'queries once for multiple lookups on the same tax_id' do
    scientific_count = 0
    common_count     = 0
    ancestor_count   = 0

    Taxdump::Name.stub :scientific_names, ->(_) { scientific_count += 1; {9606 => 'Homo sapiens'} } do
      Taxdump::Name.stub :common_names, ->(_) { common_count += 1; {9606 => 'human'} } do
        Taxdump::Node.stub :ancestor_names, ->(_) { ancestor_count += 1; {9606 => %w[Eukaryota]} } do
          cache = Flatfile::TaxIdCache.new

          cache.scientific_name(9606)
          cache.common_name(9606)
          cache.ancestor_names(9606)

          assert_equal 1, scientific_count
          assert_equal 1, common_count
          assert_equal 1, ancestor_count
        end
      end
    end
  end
end
