require_relative '../config/environment'

require 'thor'

using FetchRaiseError

API_URL = "#{Rails.application.config_for(:app).app_url!}/api"

class TestBioProject < Thor
  def self.exit_on_failure? = true

  desc 'dump', 'Dump BioProject XMLs'
  def dump
    dir = Rails.root.join('storage/bioproject_xml').tap(&:mkpath)

    cond = <<~SQL
      (submission_id, version) IN (
        SELECT submission_id, MAX(version)
        FROM xml
        GROUP BY submission_id
      )
    SQL

    BioProject::XML.where(cond).find_each do |xml|
      dir.join("#{xml.submission_id}.xml").write xml.content
    end
  end

  desc 'cleanse', 'Cleanse BioProject XMLs'
  def cleanse
    src  = Rails.root.join('storage/bioproject_xml')
    dest = Rails.root.join('storage/bioproject_xml_cleaned').tap(&:mkpath)

    src.glob '*.xml' do |path|
      doc = Nokogiri::XML.parse(path.read)

      if archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')
        archive_id[:accession] ||= 'PRJDB0000'
        archive_id[:archive]   ||= 'DDBJ'
      end

      doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism')&.remove_attribute 'taxID'
      doc.at('/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate')&.remove

      dest.join(path.basename).write doc.to_xml
    end
  end

  desc 'validate', 'Validate BioProject XMLs'
  def validate
    src  = Rails.root.join('storage/bioproject_xml_cleaned')
    dest = Rails.root.join('storage/bioproject_validate').tap(&:mkpath)

    Parallel.each src.glob('*.xml'), in_threads: 3 do |path|
      say path.basename

      res = path.open {|file|
        body = fetch("#{API_URL}/validations/via_file", **{
          method: :post,

          body: Fetch::FormData.build(
            db:                 'BioProject',
            'BioProject[file]': file
          )
        }).json

        wait_for_finish(body.fetch(:url))
      }

      dest.join("#{path.basename('.xml')}.json").write JSON.pretty_generate(res.json)
    end
  end

  desc 'submit', 'Submit BioProject JSONs'
  def submit
    json_src = Rails.root.join('storage/bioproject_validate')
    xml_src  = Rails.root.join('storage/bioproject_xml_cleaned')
    dest     = Rails.root.join('storage/bioproject_submit').tap(&:mkpath)

    Parallel.each json_src.glob('*.json'), in_threads: 3 do |path|
      json = JSON.parse(path.read, symbolize_names: true)

      next unless json.fetch(:validity) == 'valid'

      xml        = xml_src.join("#{path.basename('.json')}.xml")
      doc        = Nokogiri::XML.parse(xml.read)
      visibility = doc.at('/PackageSet/Package/Submission/Submission/Description/Hold') ? 'private' : 'public'

      res = begin
        fetch("#{API_URL}/submissions", **{
          method: :post,

          body: Fetch::URLSearchParams.new(
            db:            'BioProject',
            validation_id: json.fetch(:id),
            visibility:,
            umbrella:      false
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

  desc 'classify', 'Classify BioProject JSONs'
  def classify
    src = Rails.root.join('storage/bioproject_validate')

    src.glob '*.json' do |path|
      json     = JSON.parse(path.read, symbolize_names: true)
      validity = json.fetch(:validity)

      errors = json.fetch(:results).flat_map {
        _1.fetch(:details)
      }.select {
        _1.fetch(:severity) == 'error'
      }

      say "#{path.basename('.json')}: #{validity}".then {|banner|
        if errors.empty?
          banner
        else
          messages = errors.map {
            _1 => { code:, message: }
            "[#{code}] #{message}"
          }

          "#{banner} (#{messages.join('; ')})"
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

TestBioProject.start(ARGV)
