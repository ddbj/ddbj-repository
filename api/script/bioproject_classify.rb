require_relative '../config/environment'

src = Rails.root.join('tmp/bioproject_validate')

src.glob '*.json' do |path|
  json     = JSON.parse(path.read, symbolize_names: true)
  validity = json.fetch(:validity)

  errors = json.fetch(:results).flat_map {
    _1.fetch(:details)
  }.select {
    _1.fetch(:severity) == 'error'
  }

  puts "#{path.basename('.json')}: #{validity}".then { |msg|
    if errors.empty?
      msg
    else
      "#{msg} (#{errors.map { _1.fetch(:message) }.join(', ')})"
    end
  }
end
