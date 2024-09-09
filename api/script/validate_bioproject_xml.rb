require_relative '../config/environment'

def fetch(path, **opts)
  Fetch::API.fetch("http://localhost:3000#{path}", **{
    headers: {
      Authorization: "Bearer #{ENV.fetch('API_TOKEN')}"
    },

    **opts
  }).tap { |res|
    raise "#{res.status} #{res.status_text}: #{res.body}" unless res.ok
  }
end

def wait_for_finish(id)
  loop do
    res = fetch("/api/validations/#{id}")

    case res.json.fetch(:progress)
    when "waiting", "running"
      sleep 1
    else
      return res
    end
  end
end

src  = Rails.root.join('tmp/bioproject_xml_no_tax_id')
dest = Rails.root.join('tmp/bioproject_xml_validate').tap(&:mkpath)

Parallel.each src.glob('*.xml'), in_threads: 3 do |path|
  puts path.basename

  res = path.open { |file|
    body = fetch("/api/validations/via-file", **{
      method: :post,

      body: Fetch::FormData.build(
        db:                 "BioProject",
        "BioProject[file]": file
      )
    }).json

    wait_for_finish(body.fetch(:id))
  }

  dest.join("#{path.basename(".xml")}.json").write JSON.pretty_generate(res.json)
end
