# frozen_string_literal: true

require 'pg'

module BioProject
  # Read-only connection to the D-way staging BioProject database.
  #
  # Runs from dev via an SSH local-forward tunnel:
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #
  # Then point this client at localhost:54301. In the deployed app the
  # connection goes direct to 172.19.15.12 — the host/port/etc. are
  # read from PG* env vars so libpq's standard precedence applies.
  #
  # The class is intentionally a thin wrapper around `pg`; nothing here
  # belongs in Phase 3 spike's surface beyond what the batch import needs.
  class StagingClient
    DEFAULT_OPTIONS = {
      host:     ENV.fetch('DWAY_PGHOST', 'localhost'),
      port:     ENV.fetch('DWAY_PGPORT', '54301').to_i,
      user:     ENV.fetch('DWAY_PGUSER', 'const'),
      dbname:   'bioproject',
      password: ENV['DWAY_DB_PASSWORD']
    }.freeze

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
      sql = <<~SQL
        SELECT
          s.submission_id,
          s.submitter_id,
          s.status_id,
          s.create_date,
          s.modified_date,
          s.charge_id,
          CASE
            WHEN p.submission_id IS NULL
              THEN 'no_project_row'
            WHEN NULLIF(COALESCE(p.project_id_prefix, '') || COALESCE(p.project_id_counter::text, ''), '') IS NULL
              THEN 'no_accession'
            WHEN x.content IS NULL
              THEN 'no_xml'
          END AS reason
        FROM      submission s
        LEFT JOIN project    p USING (submission_id)
        LEFT JOIN LATERAL (
          SELECT content FROM xml WHERE xml.submission_id = s.submission_id ORDER BY version DESC LIMIT 1
        ) x ON true
        WHERE     p.submission_id IS NULL
              OR  NULLIF(COALESCE(p.project_id_prefix, '') || COALESCE(p.project_id_counter::text, ''), '') IS NULL
              OR  x.content IS NULL
        ORDER BY  s.submission_id
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
