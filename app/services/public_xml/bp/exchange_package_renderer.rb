# frozen_string_literal: true

require 'nokogiri'

module PublicXML
  module Bp
    # Three-pole (三極交換) variant of PackageRenderer. Emits the same
    # <Package> body plus a <Processing owner="DDBJ" id="..." action="..."/>
    # element that tells the receiving archive (NCBI / EBI) whether this
    # record was newly released, re-released, or unchanged since our last
    # public run.
    #
    # Mirrors the legacy bpbatch BpMakeXml.makeCollabXml: Processing is
    # inserted between <Project> and <Submission> (bpbatch added it at
    # content index 1 of a minified <Package>, i.e. right after <Project>),
    # and the action attribute is one of eAdded / eUpdated / eUnchanged.
    class ExchangePackageRenderer < PackageRenderer
      ADDED     = 'eAdded'
      UPDATED   = 'eUpdated'
      UNCHANGED = 'eUnchanged'

      # `last_run`: the previous public run's `started_at`. nil on the
      # first-ever run → every record is eUnchanged, matching bpbatch's
      # null-lastRun behaviour. `exec_date`: this run's cut-off (its
      # started_at). Comparison is at date granularity because Project only
      # stores release_date / dist_date as `date` columns (D-way compared
      # full timestamps; a same-day boundary can therefore differ by a day).
      def initialize(record:, row: nil, cache: {}, last_run: nil, exec_date: nil)
        super(record:, row:, cache:)

        @last_run  = last_run
        @exec_date = exec_date
      end

      def call
        Nokogiri::XML::Builder.new {|xml|
          xml.Package {
            render_project(xml)
            render_processing(xml)
            render_submission(xml)
          }
        }.doc.root
      end

      private

      def render_processing(xml)
        xml.Processing(owner: 'DDBJ', id: processing_id, action:)
      end

      # projectIdCounter = the numeric tail of the PRJDBnnnn accession
      # (D-way's project_id_counter). Falls back to the v3 hash so the
      # renderer is unit-testable without an AR row.
      def processing_id
        accession = @row&.accession.presence || project_block['accession'].to_s

        accession[/\d+/]
      end

      # Mirror bpbatch BpMakeXml.getXmlStatus:
      #   eAdded    when release_date falls in (last_run, exec_date]
      #   eUpdated  when dist_date    falls in (last_run, exec_date]  (ADD wins)
      #   eUnchanged otherwise (including last_run nil or both dates nil)
      def action
        return UNCHANGED unless @last_run

        return ADDED   if in_window?(@row&.release_date)
        return UPDATED if in_window?(@row&.dist_date)

        UNCHANGED
      end

      def in_window?(date)
        return false unless date

        date > @last_run.to_date && (@exec_date.nil? || date <= @exec_date.to_date)
      end
    end
  end
end
