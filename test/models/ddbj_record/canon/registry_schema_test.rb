require 'test_helper'

module DDBJRecord::Canon; end

# Every path the canon registry names has to be a place in the v3 schema, of
# the kind the entry is about. `canon:registry_completeness` checks the
# registry against doc/canonical-json.md, and both named
# `source_features/*/qualifiers/*` — which the schema does not have, the
# qualifiers being under `source/` — so the ordered mode never applied there
# and nothing said so.
class DDBJRecord::Canon::RegistrySchemaTest < ActiveSupport::TestCase
  SCHEMA   = JSON.parse(Rails.root.join('schema/ddbj-record/v3.schema.json').read)
  REGISTRY = YAML.load_file(Rails.root.join('schema/canon/array-modes.yml'))

  # Strip paths no v3 field is named after. Removing a strip path needs a
  # version bump (canonical-json.md §4.6), so they stay until the next one.
  NO_FIELD = %w[/**/last_update /**/access /**/publication_date].freeze

  # JSON pointer patterns of the schema (`*` for an array element or a dict
  # value) with the JSON types found there.
  def self.places(node = SCHEMA, path = '', chain = [], found = Hash.new {|h, k| h[k] = Set.new })
    if (ref = node['$ref'])
      name = ref.delete_prefix('#/$defs/')

      return found if chain.include?(name)

      return places(SCHEMA.dig('$defs', name), path, [*chain, name], found)
    end

    %w[anyOf oneOf allOf].each do |key|
      node[key]&.each { places(it, path, chain, found) }
    end

    found[path].merge(Array(node['type']))

    node['properties']&.each do |name, sub|
      places(sub, "#{path}/#{name}", chain, found)
    end

    places(node['items'], "#{path}/*", chain, found) if node['items'].is_a?(Hash)
    places(node['additionalProperties'], "#{path}/*", chain, found) if node['additionalProperties'].is_a?(Hash)

    found
  end

  PLACES = places.freeze

  def self.pattern(path)
    segments = path.delete_prefix('/').split('/').map {|segment|
      case segment
      when '**' then '(?:/[^/]+)*'
      when '*'  then '/[^/]+'
      else "/#{Regexp.escape(segment)}"
      end
    }

    /\A#{segments.join}\z/
  end

  def self.types_at(path)
    matcher = pattern(path)

    PLACES.select {|place, _| matcher.match?(place) }.values.reduce(Set.new, :|)
  end

  test 'the schema is read' do
    assert_includes PLACES.fetch('/sequences/entries/*/source_features/*/source/qualifiers/*'), 'array'
  end

  # An unregistered list sorts as a bag, but the guard against patches into
  # bags only knows the registered ones (canonical-json.md §3.1), so every
  # list of the schema is registered.
  test 'every array of the schema is registered' do
    arrays = PLACES.select {|_, types| types.include?('array') }.keys

    unregistered = arrays.reject {|place|
      REGISTRY.fetch('arrays').each_key.any? { self.class.pattern(it).match?(place) }
    }

    assert_empty unregistered
  end

  # A diff indexes into the order `for_diff` stripping leaves, while the stored
  # state is sorted on the unstripped elements. Where elements are sorted by
  # their content (a bag, or equal keys under `ties: content`), a volatile
  # field inside one could order the two differently, and a removal would
  # take the wrong element.
  test 'no volatile path falls inside an element sorted by its content' do
    by_content = REGISTRY.fetch('arrays').filter_map {|path, rule|
      path if rule['mode'] == 'bag' || (rule['mode'] == 'keyed' && rule.fetch('ties', 'content') == 'content')
    }

    inside = PLACES.keys.select {|place| by_content.any? { self.class.pattern("#{it}/*/**").match?(place) } }

    REGISTRY.fetch('volatile_paths').each do |volatile|
      assert_empty inside.grep(self.class.pattern(volatile)), "#{volatile} falls inside an element sorted by its content"
    end
  end

  REGISTRY.fetch('arrays').each_key do |path|
    test "array mode #{path} names an array of the schema" do
      assert_includes self.class.types_at(path), 'array', "#{path} matches no array of the v3 schema"
    end
  end

  REGISTRY.dig('strings', 'paths').each_key do |path|
    test "string class #{path} names a string of the schema" do
      assert_includes self.class.types_at(path), 'string', "#{path} matches no string of the v3 schema"
    end
  end

  REGISTRY.fetch('floats').each do |path|
    test "float path #{path} names a number of the schema" do
      assert_includes self.class.types_at(path), 'number', "#{path} matches no number of the v3 schema"
    end
  end

  (REGISTRY.fetch('volatile_paths') - NO_FIELD).each do |path|
    test "volatile path #{path} names a place of the schema" do
      refute_empty self.class.types_at(path), "#{path} matches nothing in the v3 schema"
    end
  end
end
