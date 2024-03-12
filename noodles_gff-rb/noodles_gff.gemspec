require_relative 'lib/noodles_gff/version'

Gem::Specification.new do |spec|
  spec.name    = 'noodles_gff'
  spec.version = NoodlesGFF::VERSION
  spec.authors = ['Keita Urashima']
  spec.email   = ['ursm@ursm.jp']

  spec.summary  = 'Ruby bindings for noodles_gff'
  spec.homepage = 'https://github.com/ursm/noodles_gff-rb'
  spec.license  = 'MIT'

  spec.files = Dir[
    'Cargo.lock',
    'Cargo.toml',
    'LICENSE.txt',
    'README.md',
    'ext/noodles_gff/Cargo.toml',
    'ext/noodles_gff/extconf.rb',
    'ext/noodles_gff/src/**/*.rs',
    'lib/**/*.rb',
  ]

  spec.require_paths = ['lib']
  spec.extensions    = ['ext/noodles_gff/Cargo.toml']
end
