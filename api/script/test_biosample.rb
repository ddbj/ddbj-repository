require_relative '../config/environment'

require 'thor'

using FetchRaiseError

class TestBioSample < Thor
  def self.exit_on_failure? = true

  desc 'dump', 'Dump BioSample XMLs'
  def dump
    dir = Rails.root.join('tmp/biosample_xml').tap(&:mkpath)

    BioSample::Submission.includes(samples: :xmls).find_each do |submission|
      xmls = submission.samples.map { |sample|
        sample.xmls.sort_by(&:version).last
      }

      xml = Nokogiri::XML::Builder.new { |xml|
        xml.BioSampleSet do
          xmls.each do |biosample|
            xml << biosample.content
          end
        end
      }.to_xml

      dir.join("#{submission.submission_id}.xml").write xml
    end
  end

  desc 'validate', 'Validate BioSample XMLs'
  def validate
    src  = Rails.root.join('tmp/biosample_xml')
    dest = Rails.root.join('tmp/biosample_validate').tap(&:mkpath)

    Parallel.each src.glob('*.xml'), in_threads: 3 do |path|
      say path.basename

      res = path.open { |file|
        body = fetch("#{ENV.fetch('API_URL')}/validations/via-file", **{
          method: :post,

          body: Fetch::FormData.build(
            db:                'BioSample',
            'BioSample[file]': file
          )
        }).ensure_ok.json

        wait_for_finish(body.fetch(:url))
      }

      dest.join("#{path.basename('.xml')}.json").write JSON.pretty_generate(res.json)
    end
  end

  desc 'submit', 'Submit BioSample JSONs'
  def submit
    src  = Rails.root.join('tmp/biosample_validate')
    dest = Rails.root.join('tmp/biosample_submit').tap(&:mkpath)

    Parallel.each src.glob('*.json'), in_threads: 3 do |path|
      json = JSON.parse(path.read, symbolize_names: true)

      next unless json.fetch(:validity) == 'valid'

      res = fetch("#{ENV.fetch('API_URL')}/submissions", **{
        method: :post,

        body: Fetch::URLSearchParams.new(
          db:            'BioSample',
          validation_id: json.fetch(:id),
          visibility:    'public'
        )
      })

      if res.status == 422 && res.json.fetch(:error).include?('Validation is already submitted')
        say "#{path.basename}: skipped"
        next
      end

      body = res.ensure_ok.json
      res  = wait_for_finish(body.fetch(:url))

      dest.join(path.basename).write JSON.pretty_generate(res.json)

      say "#{path.basename}: submitted"
    end
  end

  private

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
end

TestBioSample.start(ARGV)
