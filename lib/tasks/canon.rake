namespace :canon do
  desc 'Verify V3 Data class members match schema/canon/v3-fields.yml'
  task fields_check: :environment do
    manifest = YAML.load_file(Rails.root.join('schema/canon/v3-fields.yml')).fetch('classes')

    drift = manifest.each_with_object({}) {|(name, expected), acc|
      klass = DDBJRecord::V3.const_get(name)
      actual = klass.members.map(&:to_s)

      next if actual == expected

      acc[name] = {expected:, actual:, missing: expected - actual, extra: actual - expected}
    }

    if drift.empty?
      puts "OK: #{manifest.size} V3 Data classes match manifest."
    else
      drift.each do |name, diff|
        warn "DRIFT #{name}:"
        warn "  missing: #{diff[:missing].inspect}" if diff[:missing].any?
        warn "  extra:   #{diff[:extra].inspect}"   if diff[:extra].any?
      end

      abort "#{drift.size} class(es) drifted from manifest."
    end
  end

  desc 'Verify schema/canon/array-modes.yml covers every path promised by canonical-json.md'
  task registry_completeness: :environment do
    # Expected paths drawn from tmp/data-migration/canonical-json.md, frozen
    # at ddbj-canon/v1. Each entry is a concrete JSON Pointer (wildcards in
    # the registry are exercised by a representative concrete pointer) and
    # the expected classification.
    #
    # Spec sources are cited inline as `(canonical-json.md §<section>)`.
    # Updating any entry below requires re-reading the cited section.

    # ----- §3.1 / §6 Array modes ------------------------------------------
    # Listed as "ordered" in §3.1 paragraphs and §6 tables.
    expected_arrays = {
      # §3.1 ordered
      '/submission/submitters'                              => 'ordered',
      '/sequences/entries'                                  => 'ordered',
      '/sequences/entries/0/source_features'                => 'ordered',
      '/sequences/entries/0/comments'                       => 'ordered',
      '/experiments/0/spot_descriptor/reads'                => 'ordered',
      '/experiments/0/processing'                           => 'ordered',
      '/analyses/0/processing'                              => 'ordered',
      '/runs/0/files'                                       => 'ordered',
      '/analyses/0/files'                                   => 'ordered',
      '/project/publications/0/authors'                     => 'ordered',
      '/provenance/gff/pragmas'                             => 'ordered',
      '/sequences/entries/0/source_features/0/qualifiers/x' => 'ordered',
      '/features/0/qualifiers/x'                            => 'ordered',

      # §3.1 keyed (table)
      '/samples'                                            => 'keyed',
      '/relations'                                          => 'keyed',
      '/submission/attributes'                              => 'keyed',
      '/samples/0/attributes'                               => 'keyed',
      '/assembly/attributes'                                => 'keyed',
      '/datasets/0/attributes'                              => 'keyed',
      '/project/publications'                               => 'keyed',
      '/project/grants'                                     => 'keyed',
      '/access_control/dacs'                                => 'keyed',
      '/access_control/dacs/0/contacts'                     => 'keyed',
      '/datasets'                                           => 'keyed',
      '/submission/st26/invention_titles'                   => 'keyed',

      # §3.1 bag (named in body) + §6 tables
      '/experiments'                                        => 'bag',
      '/runs'                                               => 'bag',
      '/analyses'                                           => 'bag',
      '/features'                                           => 'bag',
      '/project/study_types'                                => 'bag',
      '/project/keywords'                                   => 'bag',
      '/project/locus_tag_prefix'                           => 'bag',
      '/project/target/data_types'                          => 'bag',
      '/datasets/0/dataset_types'                           => 'bag',
      '/sequences/entries/0/structured_comments'            => 'bag',
      '/submission/submitters/0/organizations'              => 'bag',
      '/experiments/0/targeted_loci'                        => 'bag',
      '/features/0/parent_ids'                              => 'bag'
    }.freeze

    # ----- §2.2 / §6 String classes ---------------------------------------
    # Default per registry is `multi_line`; entries here cover every
    # explicit single_line / sequence call-out from §2.2 plus §6 table.
    expected_strings = {
      # §2.2 sequence carve-out
      '/sequences/entries/0/sequence'                       => 'sequence',

      # §2.2 single-line paragraph + §6 rows
      '/submission/hold_date'                               => 'single_line',
      '/submission/st26/filing_date'                        => 'single_line',
      '/submission/st26/production_date'                    => 'single_line',
      '/submission/submitters/0/email'                      => 'single_line',
      '/project/publications/0/doi'                         => 'single_line',
      '/project/publications/0/pubmed_id'                   => 'single_line',
      '/access_control/policy/policy_url'                   => 'single_line',
      '/submission/submitters/0/orcid'                      => 'single_line',
      '/submission/submitters/0/organizations/0/ror_id'     => 'single_line',
      '/submission/st26/invention_titles/0/language_code'   => 'single_line',
      '/runs/0/files/0/checksum'                            => 'single_line',
      '/relations/0/properties/x'                           => 'single_line',
      '/project/relevance/x'                                => 'single_line',

      # §2.2 multi-line examples (default class — sanity check the default)
      '/project/description'                                => 'multi_line',
      '/samples/0/attributes/0/value'                       => 'multi_line',
      '/sequences/entries/0/comments/0'                     => 'multi_line',
      '/experiments/0/library/construction_protocol'        => 'multi_line',
      '/experiments/0/platform/array_description'           => 'multi_line'
    }.freeze

    # ----- §4 Volatile paths ----------------------------------------------
    # §4.3 enumerates the stripped subtrees; concrete pointers below
    # exercise each registry pattern.
    expected_volatile = [
      '/provenance',
      '/provenance/source_format',
      '/provenance/gff/pragmas',
      '/schema_version',
      '/project/accession',
      '/samples/0/accession',
      '/experiments/0/accession',
      '/runs/0/accession',
      '/analyses/0/accession',
      '/sequences/entries/0/accession',
      '/datasets/0/accession',
      '/assembly/accession',
      '/access_control/policy/accession',
      '/last_update',
      '/access',
      '/publication_date'
    ].freeze

    classifier = DDBJRecord::Canonicalizer::PathClassifier

    failures = []

    expected_arrays.each do |path, expected|
      actual = classifier.array_mode(path)
      failures << "FAIL: #{path} expected #{expected} got #{actual}" unless actual == expected
    end

    expected_strings.each do |path, expected|
      actual = classifier.string_class(path)
      failures << "FAIL: #{path} expected #{expected} got #{actual}" unless actual == expected
    end

    expected_volatile.each do |path|
      # VolatileStripper drops a subtree as soon as any ancestor matches the
      # registry, so the spec's "/provenance (subtree)" only needs `/provenance`
      # to match — descendants inherit. Walk up the ancestor chain to mirror
      # that semantics.
      segments = path.split('/', -1).drop(1)
      ancestors = (1..segments.length).map {|n| '/' + segments.first(n).join('/') }

      next if ancestors.any? {|ancestor| classifier.volatile?(ancestor) }

      failures << "FAIL: #{path} expected volatile got non-volatile"
    end

    array_count    = DDBJRecord::Canonicalizer::Registry.arrays.size
    string_count   = DDBJRecord::Canonicalizer::Registry.strings.fetch('paths').size
    volatile_count = DDBJRecord::Canonicalizer::Registry.volatile_paths.size

    puts "#{array_count} arrays / #{string_count} strings / #{volatile_count} volatile paths registered."
    puts "Spec coverage: #{expected_arrays.size} array / #{expected_strings.size} string / #{expected_volatile.size} volatile assertions."

    if failures.empty?
      puts 'OK: registry covers every path promised by canonical-json.md.'
    else
      failures.each {|line| warn line }
      abort "#{failures.size} registry coverage failure(s)."
    end
  end
end
