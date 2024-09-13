require_relative '../config/environment'

class AlreadySubmitted < StandardError; end

def fetch(url, **opts)
  Fetch::API.fetch(url, **{
    headers: {
      Authorization:    "Bearer #{ENV.fetch('API_KEY')}",
      'X-Dway-User-Id': ENV['PROXY_USER_ID']
    }.compact,

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

def wait_for_finish(url)
  loop do
    res = fetch(url)

    case res.json.fetch(:progress)
    when "waiting", "running"
      sleep 1
    else
      return res
    end
  end
end

json_src = Rails.root.join('tmp/bioproject_validate')
xml_src  = Rails.root.join('tmp/bioproject_xml_cleaned')
dest     = Rails.root.join('tmp/bioproject_submit').tap(&:mkpath)

Parallel.each json_src.glob('*.json'), in_threads: 3 do |path|
  json = JSON.parse(path.read, symbolize_names: true)

  next unless json.fetch(:validity) == 'valid'

  xml        = xml_src.join("#{path.basename('.json')}.xml")
  doc        = Nokogiri::XML.parse(xml.read)
  visibility = doc.at("/PackageSet/Package/Submission/Submission/Description/Hold") ? 'private' : 'public'

  body = fetch("#{ENV.fetch('API_URL')}/submissions", **{
    method: :post,

    body: Fetch::URLSearchParams.new(
      db:            'BioProject',
      validation_id: json.fetch(:id),
      visibility:,
      umbrella:      false
    )
  }).json

  res = wait_for_finish(body.fetch(:url))

  dest.join(path.basename).write JSON.pretty_generate(res.json)

  puts "#{path.basename}: submitted"
rescue AlreadySubmitted
  puts "#{path.basename}: skipped"
end
