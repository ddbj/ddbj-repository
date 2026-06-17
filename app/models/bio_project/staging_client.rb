# frozen_string_literal: true

require 'pg'

module BioProject
  # Read-only connection to the D-way BioProject database.
  #
  # Connection options come from DataMigration::DwayDefaults — env vars
  # override the parsed xsmdb URL credential, which in turn overrides
  # the hardcoded localhost default. For local SSH-tunnel usage:
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails data_migration:import_bp_batch
  #
  # In the deployed app no env vars are needed; the xsmdb URL already
  # points at the right Postgres instance.
  #
  # The class is intentionally a thin wrapper around `pg`; nothing here
  # belongs in Phase 3 spike's surface beyond what the batch import needs.
  class StagingClient
    DEFAULT_OPTIONS = DataMigration::DwayDefaults.options(dbname: 'bioproject').freeze

    Submission = Data.define(:psub_id, :submitter_id, :status_id, :accession, :project_type, :xml)

    def initialize(**overrides)
      @conn = PG.connect(**DEFAULT_OPTIONS.merge(overrides))
      @conn.exec('SET search_path TO mass')
    end

    def close
      @conn.close
    end

    # PSUB ids of every submission that has a project row, ordered for
    # stable resume. `after` lets the batch task pick up where a prior run
    # left off. `limit` nil → all rows.
    def submission_ids(limit: nil, after: nil)
      sql = +'SELECT submission_id FROM submission JOIN project USING (submission_id)'
      params = []
      if after
        sql << ' WHERE submission_id > $1'
        params << after
      end
      sql << ' ORDER BY submission_id'
      sql << " LIMIT #{limit.to_i}" if limit

      @conn.exec_params(sql, params).column_values(0)
    end

    # Excluded BP submissions — rows that the regular `submission_ids` →
    # `fetch` → Importer pipeline would silently drop. Three categories:
    #
    #   - no_project_row: in mass.submission but no mass.project row at all.
    #     Filtered OUT by `submission_ids`'s INNER JOIN so the importer
    #     never sees them. Curator decides whether to recover or skip.
    #   - no_accession: project row exists but project_id_prefix +
    #     project_id_counter is empty — Importer returns :no_accession.
    #     The XML <ArchiveID> attribute is intentionally NOT consulted
    #     (Converter takes DB-only post-2026-06-03; see converter.rb
    #     accession comment) so this SQL definition matches Importer behavior.
    #   - no_xml: project row exists but no `xml.content` row — Importer
    #     records :no_xml. Typically zero on staging; production unknown.
    #
    # Curator-facing fields only: id / submitter / status / dates /
    # charge_id. No payload bytes (XML) — operators can dig in via the
    # admin show or D-way directly if needed.
    Excluded = Data.define(:psub_id, :reason, :submitter_id, :status_id, :create_date, :modified_date, :charge_id)

    def enumerate_excluded
      # Per-row classification lives in a CTE so the predicate is defined
      # exactly once and consumed by both the reason CASE and the WHERE
      # filter — refactoring the accession definition (e.g. trimming
      # whitespace) can never desync the two and produce reason=NULL rows.
      #
      # `project_id_prefix || project_id_counter::text` uses PG's
      # NULL-propagating concat operator on purpose: it matches `fetch`'s
      # accession projection (line below) byte-for-byte, so a row that
      # `fetch` would deliver as accession=NULL is exactly the row this
      # method labels :no_accession — Importer behavior and this SQL are
      # symmetric by construction.
      #
      # The LATERAL projects `1 AS present` instead of the XML body: the
      # method only needs IS NULL, never the content, so there is no
      # reason to detoast and ship potentially-MB-sized XML over the
      # wire for every excluded row.
      #
      # CASE branch order is "most fundamental defect first" — a row with
      # both blank accession AND no xml gets reason='no_accession' and
      # the operator addresses that first; re-running the import after
      # they populate the accession will surface the next defect.
      sql = <<~SQL
        WITH classified AS (
          SELECT
            s.submission_id,
            s.submitter_id,
            s.status_id,
            s.create_date,
            s.modified_date,
            s.charge_id,
            (p.submission_id IS NULL)                                     AS missing_project,
            (p.project_id_prefix || p.project_id_counter::text IS NULL)   AS missing_accession,
            (xml_match.present IS NULL)                                   AS missing_xml
          FROM      submission s
          LEFT JOIN project    p USING (submission_id)
          LEFT JOIN LATERAL (
            SELECT 1 AS present FROM xml
            WHERE xml.submission_id = s.submission_id
            ORDER BY version DESC LIMIT 1
          ) xml_match ON true
        )
        SELECT submission_id, submitter_id, status_id, create_date, modified_date, charge_id,
               CASE
                 WHEN missing_project   THEN 'no_project_row'
                 WHEN missing_accession THEN 'no_accession'
                 WHEN missing_xml       THEN 'no_xml'
               END AS reason
        FROM     classified
        WHERE    missing_project OR missing_accession OR missing_xml
        ORDER BY submission_id
      SQL

      @conn.exec(sql).map {|row|
        Excluded.new(
          psub_id:       row['submission_id'],
          reason:        row['reason'],
          submitter_id:  row['submitter_id'],
          status_id:     row['status_id']&.to_i,
          create_date:   row['create_date'],
          modified_date: row['modified_date'],
          charge_id:     row['charge_id']&.to_i
        )
      }
    end

    # Returns a Submission Data object, or nil if no project row is present.
    def fetch(psub_id)
      row = @conn.exec_params(<<~SQL, [psub_id]).first
        SELECT s.submission_id,
               s.submitter_id,
               s.status_id,
               p.project_id_prefix || p.project_id_counter AS accession,
               p.project_type,
               x.content AS xml
        FROM   submission s
        JOIN   project p USING (submission_id)
        LEFT JOIN LATERAL (
          SELECT content FROM xml WHERE xml.submission_id = s.submission_id ORDER BY version DESC LIMIT 1
        ) x ON true
        WHERE  s.submission_id = $1
      SQL

      return nil unless row

      Submission.new(
        psub_id:      row['submission_id'],
        submitter_id: row['submitter_id'],
        status_id:    row['status_id'].to_i,
        accession:    row['accession'],
        project_type: row['project_type'],
        xml:          row['xml']
      )
    end
  end
end
