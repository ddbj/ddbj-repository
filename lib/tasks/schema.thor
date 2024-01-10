require 'json'
require 'pathname'
require 'yaml'

class Schema < Thor
  include Thor::Actions

  DIR = Pathname.new(File.expand_path('../../schema', __dir__))

  def self.exit_on_failure? = true

  desc 'generate', 'Generate openapi.yml and openapi.json'
  def generate
    dbs = YAML.load_file(DIR.join('db.yml'), symbolize_names: true)

    DIR.join('db.json').write JSON.pretty_generate(dbs)

    erb = ERB.new(DIR.join('openapi.yml.erb').read, trim_mode: '-')

    DIR.join('openapi.yml').write erb.result_with_hash(dbs:)

    yaml = YAML.load_file(DIR.join('openapi.yml'))

    DIR.join('openapi.json').write JSON.pretty_generate(yaml)
  end
end
