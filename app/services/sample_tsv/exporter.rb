# frozen_string_literal: true

require 'csv'

module SampleTSV
  # Renders a submission's samples (typed columns + v3 attribute bag)
  # as a TSV string suitable for download, round-trip editing in a
  # spreadsheet, and re-upload via Importer.
  #
  # Column layout:
  #   1. sample_name  — identifier (= v3 samples[*].alias). Read-only.
  #   2. accession    — AR Sample#accession; not in v3 (volatile-stripped).
  #                      Read-only — Importer ignores it.
  #   3. status       — AR Sample#status enum value.
  #   4. assignee_uid — User#uid of the assignee, blank if unassigned.
  #   5..N. attribute names (column union sorted across all samples'
  #         v3 attribute bags).
  #
  # Blank cells in attribute columns mean "this sample has no value
  # for that attribute" on the way out; on the way back the Importer
  # interprets blank as DELETE per design B(ii).
  class Exporter
    def initialize(submission)
      @submission = submission
    end

    # Streams the TSV. Yields header line first, then one line per
    # sample. Callers that want a single string can `.to_a.join`.
    def each
      return enum_for(__method__) unless block_given?

      v3_by_alias    = build_v3_index
      attribute_keys = collect_attribute_keys(v3_by_alias.values)
      header         = SampleTSV::COLUMNS + attribute_keys

      yield to_tsv_line(header)

      @submission.samples.includes(:assignee).order(:id).find_each do |sample|
        v3_sample = v3_by_alias[sample.sample_name] || {}
        attrs     = (v3_sample['attributes'] || []).to_h {|a| [a['name'], a['value']] }

        row = [
          sample.sample_name,
          sample.accession,
          sample.status,
          sample.assignee&.uid
        ] + attribute_keys.map { attrs[it] }

        yield to_tsv_line(row)
      end
    end

    private

    def build_v3_index
      record = @submission.materialised_record || {}
      Array(record['samples']).index_by { it['alias'] }
    end

    # Reserved column names are filtered so that a v3 attribute named
    # `status` or `accession` (etc.) doesn't double-emit and lose data
    # on the round trip — the Importer would discard the second slot
    # as a reserved col.
    def collect_attribute_keys(v3_samples)
      keys = v3_samples.flat_map {|s| Array(s['attributes']).map { it['name'] } }.compact.uniq
      (keys - SampleTSV::COLUMNS).sort
    end

    # Tab/newline are the TSV field/record separators. Smashing them
    # to spaces is the standard lossy-but-safe approach (curators
    # editing in Excel never see tabs in cells anyway). nil → empty
    # string. Anything else → to_s.
    def to_tsv_line(row)
      "#{row.map { sanitize(it) }.join("\t")}\n"
    end

    def sanitize(value)
      return '' if value.nil?

      value.to_s.tr("\t\r\n", '   ')
    end
  end
end
