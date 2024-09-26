require_relative '../config/environment'

using FetchRaiseError

def fetch(url, **opts)
  Retriable.with_context(:fetch) {
    Fetch::API.fetch(url, **{
      headers: {
        Authorization:    "Bearer #{ENV.fetch('API_KEY')}",
        'X-Dway-User-Id': ENV['PROXY_USER_ID']
      }.compact,

      **opts
    })
  }
end

def wait_for_finish(url)
  loop do
    res = fetch(url).ensure_ok

    case res.json.fetch(:progress)
    when 'waiting', 'running'
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
  visibility = doc.at('/PackageSet/Package/Submission/Submission/Description/Hold') ? 'private' : 'public'

  res = fetch("#{ENV.fetch('API_URL')}/submissions", **{
    method: :post,

    body: Fetch::URLSearchParams.new(
      db:            'BioProject',
      validation_id: json.fetch(:id),
      visibility:,
      umbrella:      false
    )
  })

  if res.status == 422 && res.json.fetch(:error).end_with?('Validation is already submitted')
    puts "#{path.basename}: skipped"
    next
  end

  body = res.ensure_ok.json
  res  = wait_for_finish(body.fetch(:url))

  dest.join(path.basename).write JSON.pretty_generate(res.json)

  puts "#{path.basename}: submitted"
end
