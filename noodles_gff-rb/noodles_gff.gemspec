require_relative 'lib/noodles_gff/version'

Gem::Specification.new do |spec|
  spec.name    = 'noodles_gff'
  spec.version = NoodlesGFF::VERSION
  spec.authors = ['Keita Urashima']
  spec.email   = ['ursm@ursm.jp']

  spec.summary  = 'Ruby bindings for noodles_gff'
  spec.homepage = 'https://github.com/ursm/noodles_gff-rb'
  spec.license  = 'MIT'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end

  spec.require_paths = ['lib']
  spec.extensions    = ['ext/noodles_gff/Cargo.toml']
end
