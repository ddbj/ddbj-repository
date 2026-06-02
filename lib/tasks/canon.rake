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
end
