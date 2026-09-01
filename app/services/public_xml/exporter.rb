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
    # `kind`: 'public' | 'exchange' (exchange is BP-only)
    # `output_dir`, `filename`, `renderer_class`, `scope` are injected so
    # the per-DB job can supply its own concrete configuration without
    # forcing this class to know about BP vs BS specifics.
    # `renderer_options` are extra keyword args splatted into every
    # `renderer_class.new` call — run-level context a renderer needs beyond
    # the per-record record/row/cache (the exchange renderer uses it for
    # the last_run / exec_date delta window). Empty for the public renderers.
    def initialize(db:, kind:, output_dir:, filename:, renderer_class:, scope:, renderer_options: {})
      @db               = db
      @kind             = kind
      @output_dir       = Pathname.new(output_dir)
      @filename         = filename
      @renderer_class   = renderer_class
      @scope            = scope
      @renderer_options = renderer_options
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

          node = @renderer_class.new(record: v3, row: record, cache: render_cache, **@renderer_options).call
          next unless node

          io.write indent_fragment(node)
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

    # The declaration is written out: bsbatch declared ISO-8859-1 and
    # escaped everything above it, so a consumer that trusts the prolog
    # rather than sniffing gets mojibake on a Japanese organization name
    # the moment the file starts arriving as undeclared UTF-8.
    def write_header(io)
      io.write(%(<?xml version="1.0" encoding="UTF-8"?>\n))
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

    # Nokogiri serialises a node at the root level, with no leading
    # indent, so the children of the root element need one tab adding to
    # sit a level in — matching the legacy tab-indented output.
    #
    # By serialising the record inside a stand-in root rather than
    # prefixing the lines of the finished string. Nokogiri indents
    # structure but never the inside of a text node, and prefixing by
    # hand could not tell the two apart: it pushed a tab into the second
    # and every later line of every multi-line value, which is most of
    # the freeform ones. The file said something different from the
    # record, and nothing compared them.
    def indent_fragment(node)
      holder.add_child(node)

      holder.to_xml(indent: 1, indent_text: "\t").lines[1..-2].join
    ensure
      holder.children.unlink
    end

    def holder
      @holder ||= Nokogiri::XML::Document.new.then {
        it.root = it.create_element(root_element)
        it.root
      }
    end
  end
end
