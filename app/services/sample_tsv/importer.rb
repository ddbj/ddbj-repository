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
    Result = Struct.new(:total, :processed, :failed, :error_report, :fatal_error, keyword_init: true)

    BOM = '﻿'

    def initialize(submission:, tsv_body:, actor:)
      @submission = submission
      @tsv_body   = tsv_body
      @actor      = actor
    end

    def call
      # CSV.parse decodes the body up front but for streaming we use
      # CSV.foreach indirectly via the row-each block below. We still
      # need a single up-front pass to discover the header set, which
      # `headers: true` gives us via the first parsed row.
      rows           = CSV.parse(strip_bom(@tsv_body), col_sep: "\t", headers: true)
      attribute_cols = rows.headers.to_a.reject {|h| h.nil? || SampleTSV::COLUMNS.include?(h) }

      unless rows.headers.include?(SampleTSV::IDENTIFIER_COL)
        return Result.new(
          total:        0,
          processed:    0,
          failed:       0,
          error_report: nil,
          fatal_error:  "TSV is missing the required `#{SampleTSV::IDENTIFIER_COL}` column."
        )
      end

      sample_by_name = @submission.samples.includes(:assignee).index_by(&:sample_name)
      user_by_uid    = preload_assignee_uids(rows)

      valid, errors = partition_rows(rows, attribute_cols, sample_by_name, user_by_uid)

      apply!(valid, attribute_cols) if valid.any?

      Result.new(
        total:        rows.size,
        processed:    valid.size,
        failed:       errors.size,
        error_report: errors.any? ? build_error_report(rows.headers, errors) : nil,
        fatal_error:  nil
      )
    end

    private

    # Excel (and other spreadsheet exports) prepend a UTF-8 BOM to the
    # file. Left in, the byte-order mark fuses to the first header name
    # and silently breaks the `sample_name` lookup. Strip once at the
    # entry point so downstream parsing stays simple.
    def strip_bom(body)
      body.start_with?(BOM) ? body.sub(BOM, '') : body
    end

    def preload_assignee_uids(rows)
      uids = rows.filter_map { it['assignee_uid']&.strip.presence }.uniq
      return {} if uids.empty?

      User.where(uid: uids).index_by(&:uid)
    end

    def partition_rows(rows, attribute_cols, sample_by_name, user_by_uid)
      valid  = []
      errors = []

      rows.each do |row|
        sample = sample_by_name[row[SampleTSV::IDENTIFIER_COL].to_s.strip.presence]
        unless sample
          errors << [row, "unknown #{SampleTSV::IDENTIFIER_COL}"]
          next
        end

        # Empty `status` cell is interpreted as "leave the AR enum
        # alone". An explicit value is enum-validated up front so we
        # don't fail mid-apply.
        status = row['status']&.strip.presence
        if status && !Sample.statuses.key?(status)
          errors << [row, "unknown status: #{status}"]
          next
        end

        assignee_id =
          case row['assignee_uid']&.strip
          when nil, ''             then sample.assignee_id # leave as-is
          when '-'                 then nil                # explicit unassign
          else
            user = user_by_uid[row['assignee_uid'].strip]
            unless user
              errors << [row, "unknown assignee_uid: #{row['assignee_uid']}"]
              next
            end
            user.id
          end

        attrs = attribute_cols.to_h {|col| [col, row[col]&.strip.presence] }

        valid << {
          sample:      sample,
          status:      status || sample.status,
          assignee_id: assignee_id,
          attrs:       attrs
        }
      end

      [valid, errors]
    end

    def apply!(valid, attribute_cols)
      # Wrap the v3 chain append + the AR typed-column sync so a
      # mid-loop DB error rolls BOTH back instead of leaving the chain
      # patch committed while half the Sample rows are still on the
      # old values (admin show would diverge from v3 forever).
      ActiveRecord::Base.transaction do
        base = @submission.materialised_record&.deep_dup || {'schema_version' => 'v3'}
        base['samples'] ||= []

        v3_by_alias = base['samples'].to_h { [it['alias'], it] }

        valid.each do |row|
          v3_sample = v3_by_alias[row[:sample].sample_name] || begin
            fresh = {'alias' => row[:sample].sample_name}
            base['samples'] << fresh
            v3_by_alias[row[:sample].sample_name] = fresh
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
        'taxonomy_id' => Integer(taxonomy_id.to_s, 10, exception: false),
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
    def sync_ar_columns!(valid)
      valid.each do |row|
        row[:sample].update_columns(
          status:      row[:status],
          assignee_id: row[:assignee_id],
          title:       row[:attrs]['sample_title'],
          organism:    row[:attrs]['organism'],
          taxonomy_id: Integer(row[:attrs]['taxonomy_id'].to_s, 10, exception: false)
        )
      end
    end

    def build_error_report(headers, errors)
      CSV.generate(col_sep: "\t") {|csv|
        csv << (headers + ['error'])
        errors.each do |row, reason|
          csv << (headers.map { row[it] } + [reason])
        end
      }
    end
  end
end
