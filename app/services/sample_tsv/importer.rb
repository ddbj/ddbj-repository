# frozen_string_literal: true

require 'csv'

module SampleTSV
  # Apply a curator-uploaded TSV to a BS submission. Reverse direction
  # of Exporter — see that file for the column layout.
  #
  # Per the design (B(ii)) blank cells in attribute columns DELETE the
  # attribute on the matched sample, and unknown column headers ADD new
  # attributes. Identifier columns (`sample_name`, `accession`) are
  # treated as read-only context.
  #
  # Skip-invalid semantics: each row is validated independently. Valid
  # rows are accumulated and applied as a SINGLE SubmissionUpdate so
  # the curator's intent ("the submission now matches this TSV") lands
  # as one chain entry, attributed to the curator via the `actor` arg
  # and tagged `source: :tsv_import`. Failed rows are returned in
  # `result.error_report` (a TSV body with the original cells plus an
  # `error` column the curator can fix and re-upload).
  class Importer
    Result = Struct.new(:total, :processed, :failed, :error_report, :rejections, :fatal_error, keyword_init: true)

    # One refused row, with everything needed to fix it: where it is, what
    # it is, which cell was wrong and why. The screen shows the first few
    # so the common case never needs the download.
    Rejection = Data.define(:line, :sample_name, :column, :reason) do
      def to_h = {'line' => line, 'sample_name' => sample_name, 'column' => column, 'reason' => reason}
    end

    # Reported to, not returned: checking is row-by-row and countable,
    # applying is one write. A caller that does not care passes nothing.
    class NullProgress
      def checking(*, **) = nil
      def applying(*, **) = nil
    end

    # U+FEFF (UTF-8: EF BB BF). Written via the Unicode escape so the
    # source file isn't carrying invisible zero-width bytes that look
    # like an empty string to a reviewer.
    BOM = "\u{FEFF}"

    def initialize(submission:, tsv_body:, actor:, progress: NullProgress.new)
      @submission = submission
      @tsv_body   = tsv_body
      @actor      = actor
      @progress   = progress
    end

    def call
      # CSV.parse decodes the body up front but for streaming we use
      # CSV.foreach indirectly via the row-each block below. We still
      # need a single up-front pass to discover the header set, which
      # `headers: true` gives us via the first parsed row.
      # Headers are names, and a name is its text without the spaces round it —
      # the record's canonical form strips them anyway (doc/canonical-json.md
      # §2.2). Stripping here, before anything reads them, is what lets
      # `status ` be the reserved column it was meant as rather than an
      # attribute called `status`.
      rows           = CSV.parse(strip_bom(@tsv_body), col_sep: "\t", headers: true, header_converters: ->(h) { h&.strip })
      attribute_cols = rows.headers.to_a.reject {|h| h.blank? || SampleTSV::RESERVED_COLS.include?(h) }

      unless rows.headers.include?(SampleTSV::IDENTIFIER_COL)
        return fatal("TSV is missing the required `#{SampleTSV::IDENTIFIER_COL}` column.")
      end

      # An attribute needs a name (DDBJ Record v3), so a column with values and
      # no header has nowhere to go. A column with neither — the trailing tab a
      # spreadsheet leaves — is nothing and is passed over, as it always was.
      if (column = unnamed_column_with_values(rows))
        return fatal("Column #{column} has values but no header. Every attribute needs a name: " \
                     'give the column one, or remove it.')
      end

      # Names are compared as the record stores an alias (Sample.normalise_name),
      # so a TSV downloaded before a row was renamed, or re-saved by a
      # spreadsheet with NBSP, still finds its sample.
      sample_by_name = @submission.samples.index_by { Sample.normalise_name(it.sample_name) }

      valid, errors = partition_rows(rows, attribute_cols, sample_by_name)

      if valid.any?
        @progress.applying(rows: valid.size)

        apply!(valid, attribute_cols)
      end

      Result.new(
        total:        rows.size,
        processed:    valid.size,
        failed:       errors.size,
        error_report: errors.any? ? build_error_report(rows.headers, errors) : nil,
        rejections:   errors.map { it.last.to_h },
        fatal_error:  nil
      )
    end

    private

    # Excel (and other spreadsheet exports) prepend a UTF-8 BOM to the
    # file. Left in, the byte-order mark fuses to the first header name
    # and silently breaks the `sample_name` lookup. Strip once at the
    # entry point so downstream parsing stays simple.
    def fatal(message)
      Result.new(total: 0, processed: 0, failed: 0, error_report: nil, rejections: [], fatal_error: message)
    end

    # 1-based, as a spreadsheet numbers them. By position rather than by name:
    # the columns in question have none, and two of them would share one.
    def unnamed_column_with_values(rows)
      rows.headers.each_with_index do |header, index|
        next if header.present?

        return index + 1 if rows.any? { it.fields[index].present? }
      end

      nil
    end

    def strip_bom(body)
      body.start_with?(BOM) ? body.sub(BOM, '') : body
    end

    # Row by row, and therefore countable — which is the half of the work
    # a progress bar can honestly describe. Reported every
    # PROGRESS_EVERY rows so a 100K file does not spend the import
    # writing to the progress row.
    PROGRESS_EVERY = 200

    def partition_rows(rows, attribute_cols, sample_by_name)
      valid  = []
      errors = []

      rows.each_with_index do |row, index|
        # +2: the header is line 1, and a curator counts from 1.
        line = index + 2

        report_checking(index, rows.size, errors.size)

        name   = row[SampleTSV::IDENTIFIER_COL].to_s.strip.presence
        sample = sample_by_name[Sample.normalise_name(name)]

        unless sample
          errors << [row, Rejection.new(line:, sample_name: name, column: SampleTSV::IDENTIFIER_COL,
                                        reason: 'No sample with this name in the submission')]
          next
        end

        # Empty `status` cell is interpreted as "leave the AR enum
        # alone". An explicit value is enum-validated up front so we
        # don't fail mid-apply.
        status = row['status']&.strip.presence
        if status && !Sample.statuses.key?(status)
          errors << [row, Rejection.new(line:, sample_name: name, column: 'status',
                                        reason: "#{status.inspect} is not a known status")]
          next
        end

        attrs = attribute_cols.to_h {|col| [col, row[col]&.strip.presence] }

        valid << {
          sample: sample,
          status: status || sample.status,
          attrs:  attrs
        }
      end

      @progress.checking(checked: rows.size, rejected: errors.size, total: rows.size)

      [valid, errors]
    end

    def report_checking(index, total, rejected)
      return unless (index % PROGRESS_EVERY).zero?

      @progress.checking(checked: index, rejected:, total:)
    end

    def apply!(valid, attribute_cols)
      # Wrap the v3 chain append + the AR typed-column sync so a
      # mid-loop DB error rolls BOTH back instead of leaving the chain
      # patch committed while half the Sample rows are still on the
      # old values (admin show would diverge from v3 forever).
      ActiveRecord::Base.transaction do
        base = @submission.materialised_record&.deep_dup || {'schema_version' => 'v3'}
        base['samples'] ||= []

        v3_by_alias = base['samples'].to_h { [Sample.normalise_name(it['alias']), it] }

        valid.each do |row|
          name      = Sample.normalise_name(row[:sample].sample_name)
          v3_sample = v3_by_alias[name] || begin
            fresh = {'alias' => row[:sample].sample_name}
            base['samples'] << fresh
            v3_by_alias[name] = fresh
            fresh
          end

          sync_v3_attributes!(v3_sample, row[:attrs], attribute_cols)
          sync_v3_typed_lifts!(v3_sample, row[:attrs])
        end

        @submission.append_update!(base, actor: @actor, source: :tsv_import)

        sync_ar_columns!(valid)
      end
    end

    # Replace attributes touched by this import row. Cells the curator
    # left blank ⇒ DELETE the attribute (B(ii)). Cells with a value ⇒
    # upsert. Attributes outside `attribute_cols` (curator didn't
    # touch them via TSV) are left as-is.
    def sync_v3_attributes!(v3_sample, attrs, attribute_cols)
      current = (v3_sample['attributes'] || []).each_with_object({}) {|a, h| h[a['name']] = a }

      attribute_cols.each do |name|
        value = attrs[name]
        if value.nil?
          current.delete(name)
        else
          current[name] = {'name' => name, 'value' => value}
        end
      end

      if current.empty?
        v3_sample.delete('attributes')
      else
        v3_sample['attributes'] = current.values
      end
    end

    # Keep the lifted slots (title / description / organism) in sync
    # with the bag, matching BioSample::Converter#sample_block's lift
    # logic. Without this the admin show / typed-column projections go
    # stale immediately after the curator's first TSV.
    def sync_v3_typed_lifts!(v3_sample, attrs)
      sample_title = attrs['sample_title']
      description  = attrs['description']
      organism     = attrs['organism']
      taxonomy_id  = attrs['taxonomy_id']

      assign_or_drop(v3_sample, 'title',       sample_title)
      assign_or_drop(v3_sample, 'description', description)

      org = {
        'taxonomy_id' => taxonomy_id&.strip.presence,
        'name'        => organism.presence
      }.compact

      if org.empty?
        v3_sample.delete('organism')
      else
        v3_sample['organism'] = org
      end
    end

    def assign_or_drop(hash, key, value)
      if value.nil?
        hash.delete(key)
      else
        hash[key] = value
      end
    end

    # AR Sample's typed columns are derived from v3 by the BS Importer
    # on migration. The TSV importer is the curator-driven equivalent
    # and must keep the same projection up to date — bulk_update_samples
    # / admin show queries these columns directly without parsing v3.
    #
    # A status that moves goes through `move_to_status!`, as it does from
    # the screens, so that crossing into or out of public is dated.
    def sync_ar_columns!(valid)
      valid.each do |row|
        row[:sample].update_columns(
          title:       row[:attrs]['sample_title'],
          organism:    row[:attrs]['organism'],
          taxonomy_id: DDBJRecord.taxonomy_id_number(row[:attrs]['taxonomy_id'])
        )
      end

      valid.reject { it[:status] == it[:sample].status }.group_by { it[:status] }.each do |status, rows|
        Sample.where(id: rows.map { it[:sample].id }).move_to_status!(status)
      end
    end

    def build_error_report(headers, errors)
      CSV.generate(col_sep: "\t") {|csv|
        csv << (headers + [SampleTSV::ERROR_COL])
        errors.each do |row, rejection|
          csv << (headers.map { row[it] } + [rejection.reason])
        end
      }
    end
  end
end
