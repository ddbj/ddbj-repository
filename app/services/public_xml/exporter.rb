# frozen_string_literal: true

module PublicXML
  # Walks every publicly-visible record (Project / Sample) of a database,
  # asks the per-package renderer to produce its XML fragment, and writes
  # the concatenated stream to a single file under the configured output
  # directory.
  #
  # The file is written under a temp name first (`.partial`) and renamed
  # atomically on success — consumers polling the output directory never
  # observe a half-written file. On failure the temp file is left behind
  # so the on-call can inspect it; the next successful run will overwrite
  # it.
  #
  # `PublicXMLRun` rows track the lifecycle. The same row is reused for
  # both `running` → `completed` and `running` → `failed` transitions.
  class Exporter
    # `db`: 'bioproject' | 'biosample'
    # `kind`: 'public' (Phase A) — Phase B will extend with 'exchange'
    # `output_dir`, `filename`, `renderer_class`, `scope` are injected so
    # the per-DB job can supply its own concrete configuration without
    # forcing this class to know about BP vs BS specifics.
    def initialize(db:, kind:, output_dir:, filename:, renderer_class:, scope:)
      @db             = db
      @kind           = kind
      @output_dir     = Pathname.new(output_dir)
      @filename       = filename
      @renderer_class = renderer_class
      @scope          = scope
    end

    def call
      @output_dir.mkpath

      run = PublicXMLRun.create!(
        db:         @db,
        kind:       @kind,
        status:     'running',
        started_at: Time.current
      )

      partial = @output_dir.join("#{@filename}.partial")
      final   = @output_dir.join(@filename)
      emitted = 0

      # Memoise materialised_record per submission so sibling samples of
      # the same BS submission don't repeatedly Oj.load a multi-MB blob.
      # `render_cache` is handed to every renderer so they can share
      # per-submission indices (BS uses it for samples_by_alias).
      v3_by_submission = {}
      render_cache     = {}

      partial.open('w:UTF-8') do |io|
        write_header(io)

        @scope.find_each do |record|
          v3 = v3_by_submission[record.submission_id] ||= record.submission.materialised_record
          next unless v3

          node = @renderer_class.new(record: v3, row: record, cache: render_cache).call
          next unless node

          fragment = node.to_xml(indent: 1, indent_text: "\t")
          io.write indent_fragment(fragment)
          io.write "\n"
          emitted += 1
        end

        write_footer(io)
      end

      partial.rename(final)

      run.update!(
        status:      'completed',
        emitted:     emitted,
        finished_at: Time.current
      )

      run
    rescue StandardError => e
      if run
        run.append_error!("#{e.class}: #{e.message}\n#{e.backtrace.first(20).join("\n")}")
        run.update!(status: 'failed', finished_at: Time.current)
      end

      raise
    end

    private

    def write_header(io)
      io.write("<#{root_element}>\n")
    end

    def write_footer(io)
      io.write("</#{root_element}>\n")
    end

    def root_element
      case @db
      when 'bioproject' then 'PackageSet'
      when 'biosample'  then 'BioSampleSet'
      else
        raise ArgumentError, "unknown db: #{@db}"
      end
    end

    # Nokogiri serialises each fragment at the root level (no leading
    # indent). Add one tab to every line so the children of the root
    # element sit one level in, matching the legacy bpbatch tab-indented
    # output.
    def indent_fragment(fragment)
      fragment.each_line.map { "\t#{it}" }.join
    end
  end
end
