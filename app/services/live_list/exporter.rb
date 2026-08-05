# frozen_string_literal: true

require 'pathname'

module LiveList
  # Writes the BP/BS "livelist": three tab-separated files (public /
  # suppressed / withdrawn) that tell NCBI the current status of every
  # accessioned record. Reverse of D-way's BpMakeLiveList.rb /
  # BsMakeLiveList.rb — same columns (Accession / Updated / Status), same
  # status partition, same header.
  #
  # Each file is written under a `.partial` name and renamed atomically, so
  # a consumer polling the directory never sees a half-written file. Only
  # the latest generation is kept (overwrite), unlike D-way's dated files.
  class Exporter
    # status enum name → livelist label. Only these statuses are listed;
    # everything else (private / curating / accession_issued / canceled /
    # submission_accepted) is omitted, matching D-way.
    STATUS_LABELS = {
      'public'                 => 'public',
      'temporarily_suppressed' => 'suppressed',
      'permanently_suppressed' => 'suppressed',
      'withdrawn'              => 'withdrawn'
    }.freeze

    LISTED_STATUSES = STATUS_LABELS.keys.freeze
    LABELS          = STATUS_LABELS.values.uniq.freeze # public, suppressed, withdrawn
    HEADER          = %w[Accession Updated Status].freeze
    BATCH_SIZE      = 5_000

    # `scope`: an AR relation over Project or Sample already filtered to the
    # listed statuses. `filename_prefix`: 'bioproject' | 'biosample'.
    def initialize(output_dir:, scope:, filename_prefix:)
      @output_dir      = Pathname.new(output_dir)
      @scope           = scope
      @filename_prefix = filename_prefix
    end

    def call
      @output_dir.mkpath

      ios = LABELS.index_with { partial_path(it).open('w:UTF-8') }
      ios.each_value { it.write(row(HEADER)) }

      each_in_accession_order do |record|
        label = STATUS_LABELS[record.status] or next

        ios[label].write(row([record.accession, updated(record), label]))
      end

      ios.each_value(&:close)

      LABELS.each { partial_path(it).rename(final_path(it)) }
    rescue StandardError
      ios&.each_value {|io| io.close unless io.closed? }
      raise
    end

    private

    def final_path(label)   = @output_dir.join("#{@filename_prefix}.#{label}.txt")
    def partial_path(label) = @output_dir.join("#{@filename_prefix}.#{label}.txt.partial")

    def row(fields) = "#{fields.join("\t")}\n"

    # D-way's `Updated` is project/sample.modified_date. Migrated rows carry
    # it (see the importers); rows created/edited after migration have no
    # modified_date yet, so fall back to updated_at — the row's real last
    # touch, which is what modified_date means.
    def updated(record)
      (record.modified_date || record.updated_at&.to_date)&.iso8601
    end

    # Keyset pagination on `accession` — index-backed (accession is
    # uniquely indexed on both tables), so streaming stays fast and memory
    # flat even at BS scale (millions of samples). A functional key like
    # length(accession) would give BP its numeric order but can't use the
    # index, turning every batch into a full sort — hence plain accession.
    #
    # NOTE: BS accessions are fixed width, so accession order == numeric
    # order (matches D-way). BP accessions (PRJDB2 … PRJDB20341) are NOT
    # zero-padded, so this yields lexical order (PRJDB100 before PRJDB2),
    # which differs from D-way's numeric project_id_counter order. The
    # livelist consumer is order-agnostic; revisit if strict parity is
    # needed (BP is small enough to sort in memory).
    def each_in_accession_order
      last_acc = nil

      loop do
        batch = @scope.order(:accession).limit(BATCH_SIZE)
        batch = batch.where('accession > ?', last_acc) if last_acc

        records = batch.to_a
        break if records.empty?

        records.each { yield it }

        last_acc = records.last.accession
      end
    end
  end
end
