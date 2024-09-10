require_relative '../config/environment'

class AlreadySubmitted < StandardError; end

def fetch(path, **opts)
  Fetch::API.fetch("http://localhost:3000#{path}", **{
    headers: {
      Authorization: "Bearer #{ENV.fetch('API_TOKEN')}"
    },

    **opts
  }).tap { |res|
    case res.status
    when 200..299
      # do nothing
    when 422
      if res.json[:error].end_with?('Validation is already submitted')
        raise AlreadySubmitted
      else
        raise "#{res.status} #{res.status_text}: #{res.body}"
      end
    else
      raise "#{res.status} #{res.status_text}: #{res.body}"
    end
  }
end

def wait_for_finish(id)
  loop do
    res = fetch("/api/submissions/#{id}")

    case res.json.fetch(:progress)
    when "waiting", "running"
      sleep 1
    else
      return res
    end
  end
end

json_src = Rails.root.join('tmp/bioproject_xml_validate')
xml_src  = Rails.root.join('tmp/bioproject_xml_no_tax_id')
dest     = Rails.root.join('tmp/bioproject_xml_submit').tap(&:mkpath)

json_src.glob '*.json' do |path|
  json = JSON.parse(path.read, symbolize_names: true)

  next unless json.fetch(:validity) == 'valid'

  xml        = xml_src.join("#{path.basename('.json')}.xml")
  doc        = Nokogiri::XML.parse(xml.read)
  visibility = doc.at("/PackageSet/Package/Submission/Submission/Description/Hold") ? 'private' : 'public'

  body = fetch('/api/submissions', **{
    method: :post,

    body: Fetch::URLSearchParams.new(
      'submission[validation_id]': json.fetch(:id),
      'submission[visibility]':    visibility,
      'param[umbrella]':           false
    )
  }).json

  res = wait_for_finish(body.fetch(:id))

  dest.join(path.basename).write JSON.pretty_generate(res.json)

  puts "#{path.basename}: submitted"
rescue AlreadySubmitted
  puts "#{path.basename}: skipped"
end
