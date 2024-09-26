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

src  = Rails.root.join('tmp/bioproject_xml_cleaned')
dest = Rails.root.join('tmp/bioproject_validate').tap(&:mkpath)

Parallel.each src.glob('*.xml'), in_threads: 3 do |path|
  puts path.basename

  res = path.open { |file|
    body = fetch("#{ENV.fetch('API_URL')}/validations/via-file", **{
      method: :post,

      body: Fetch::FormData.build(
        db:                 'BioProject',
        'BioProject[file]': file
      )
    }).ensure_ok.json

    wait_for_finish(body.fetch(:url))
  }

  dest.join("#{path.basename(".xml")}.json").write JSON.pretty_generate(res.json)
end
