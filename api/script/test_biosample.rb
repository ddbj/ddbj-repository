require_relative '../config/environment'

require 'thor'

using FetchRaiseError

class TestBioSample < Thor
  def self.exit_on_failure? = true

  desc 'dump', 'Dump BioSample XMLs'
  def dump
    dir = Rails.root.join('tmp/biosample_xml').tap(&:mkpath)

    BioSample::Submission.includes(samples: :xmls).find_each do |submission|
      xmls = submission.samples.filter_map { |sample|
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

  desc 'cleanse', 'Cleanse BioSample XMLs'
  def cleanse
    src  = Rails.root.join('tmp/biosample_xml')
    dest = Rails.root.join('tmp/biosample_xml_cleaned').tap(&:mkpath)

    src.glob '*.xml' do |path|
      doc = Nokogiri::XML.parse(path.read)

      doc.xpath('/BioSampleSet/BioSample/Attributes/Attribute[@attribute_name="collection_date"]').map { |attribute|
        attribute.content = '1900'
      }

      doc.xpath('/BioSampleSet/BioSample/Attributes/Attribute[@attribute_name="geo_loc_name"]').map { |attribute|
        attribute.content = 'Japan'
      }

      dest.join(path.basename).write doc.to_xml
    end
  end

  desc 'validate', 'Validate BioSample XMLs'
  def validate
    src  = Rails.root.join('tmp/biosample_xml_cleaned')
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
        }).json

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

      res = begin
        fetch("#{ENV.fetch('API_URL')}/submissions", **{
          method: :post,

          body: Fetch::URLSearchParams.new(
            db:            'BioSample',
            validation_id: json.fetch(:id),
            visibility:    'public'
          )
        })
      rescue FetchRaiseError::ClientError => e
        res = e.response

        if res.status == 422 && res.json.fetch(:error).include?('Validation is already submitted')
          say "#{path.basename}: skipped"
          next
        else
          raise
        end
      end

      body = res.json
      res  = wait_for_finish(body.fetch(:url))

      dest.join(path.basename).write JSON.pretty_generate(body)

      say "#{path.basename}: submitted"
    end
  end

  desc 'classify', 'Classify BioSample JSONs'
  def classify
    src = Rails.root.join('tmp/biosample_validate')

    src.glob '*.json' do |path|
      json     = JSON.parse(path.read, symbolize_names: true)
      validity = json.fetch(:validity)

      errors = json.fetch(:results).flat_map {
        _1.fetch(:details)
      }.select {
        _1.fetch(:severity) == 'error'
      }

      say "#{path.basename('.json')}: #{validity}".then { |msg|
        if errors.empty?
          msg
        else
          "#{msg} (#{errors.map { _1.fetch(:message) }.join(', ')})"
        end
      }
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
      }).ensure_ok
    }
  end

  def wait_for_finish(url)
    loop do
      res = fetch(url)

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
