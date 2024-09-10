require_relative '../config/environment'

src = Rails.root.join('tmp/bioproject_xml_validate')

src.glob '*.json' do |path|
  json = JSON.parse(path.read, symbolize_names: true)

  puts "#{path.basename('.json')}: #{json.fetch(:validity)}"
end
