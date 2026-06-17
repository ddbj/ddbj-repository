# frozen_string_literal: true

require 'pg'

module BioSample
  # Read-only connection to the D-way BioSample database. Same tunnel
  # pattern + connection-options precedence as BioProject::StagingClient.
  #
  # The BS schema diverges from BP: 1 submission → N samples, each sample
  # has its own accession + XML + EAV attribute rows. This client returns
  # the EAV-shaped data structure (sample row + attributes per smp_id);
  # the per-sample XML is intentionally skipped because the EAV is the
  # canonical editable form in D-way and the XML is regenerated downstream.
  class StagingClient
    DEFAULT_OPTIONS = DataMigration::DwayDefaults.options(dbname: 'biosample').freeze

    Submission = Data.define(:ssub_id, :submitter_id, :organization, :organization_url, :comment, :samples, :contacts)
    # NOTE(phase 6 deferral): :package_group is derivable from :package against
    # a known catalog version (`/package_and_group_list?version=<v>`). Today we
    # mirror staging's value as a typed column. Once Sample carries a
    # `package_version` field and we cache the catalog, this slot can become
    # an audit-only artefact and the typed column on `samples` can be dropped.
    Sample     = Data.define(:smp_id, :accession, :sample_name, :package, :package_group, :env_package, :status_id, :attributes)
    Contact    = Data.define(:email, :first, :last)

    def initialize(**overrides)
      @conn = PG.connect(**DEFAULT_OPTIONS.merge(overrides))
      @conn.exec('SET search_path TO mass')
    end

    def close
      @conn.close
    end

    def submission_ids(limit: nil, after: nil)
      sql = +'SELECT submission_id FROM submission'
      params = []
      if after
        sql << ' WHERE submission_id > $1'
        params << after
      end
      sql << ' ORDER BY submission_id'
      sql << " LIMIT #{limit.to_i}" if limit

      @conn.exec_params(sql, params).column_values(0)
    end

    # Excluded BS submissions — rows that the regular `submission_ids` →
    # `fetch` → Importer pipeline would silently drop. One category:
    #
    #   - no_samples: mass.submission row exists but has zero rows in
    #     mass.sample. Importer returns :no_samples. Typically zero on
    #     staging; production may differ.
    #
    # BS submission has no aggregate `status_id` (status is per-sample),
    # so the curator-facing fields are smaller than the BP counterpart.
    Excluded = Data.define(:ssub_id, :reason, :submitter_id, :organization, :create_date, :modified_date, :charge_id)

    def enumerate_excluded
      # NOT EXISTS instead of LEFT JOIN + GROUP BY + HAVING COUNT(...)=0:
      # production mass.sample has tens of millions of rows, and the
      # anti-join lets PG short-circuit per submission via the
      # sample.submission_id index without materializing the full join
      # or aggregating across 6 grouping columns.
      sql = <<~SQL
        SELECT   s.submission_id,
                 s.submitter_id,
                 s.organization,
                 s.create_date,
                 s.modified_date,
                 s.charge_id
        FROM     submission s
        WHERE    NOT EXISTS (SELECT 1 FROM sample sm WHERE sm.submission_id = s.submission_id)
        ORDER BY s.submission_id
      SQL

      @conn.exec(sql).map {|row|
        Excluded.new(
          ssub_id:       row['submission_id'],
          reason:        'no_samples',
          submitter_id:  row['submitter_id'],
          organization:  row['organization'],
          create_date:   row['create_date'],
          modified_date: row['modified_date'],
          charge_id:     row['charge_id']&.to_i
        )
      }
    end

    def fetch(ssub_id)
      sub_row = @conn.exec_params(<<~SQL, [ssub_id]).first
        SELECT submission_id, submitter_id, organization, organization_url, comment
        FROM   submission
        WHERE  submission_id = $1
      SQL

      return nil unless sub_row

      sample_rows = @conn.exec_params(<<~SQL, [ssub_id]).to_a
        SELECT s.smp_id, a.accession_id, s.sample_name, s.package, s.package_group, s.env_package, s.status_id
        FROM   sample s
        LEFT JOIN accession a USING (smp_id)
        WHERE  s.submission_id = $1
        ORDER BY s.smp_id
      SQL

      attrs_by_smp = @conn.exec_params(<<~SQL, [ssub_id]).to_a.group_by {|r| r['smp_id'].to_i }
        SELECT attribute_name, attribute_value, smp_id
        FROM   attribute
        WHERE  smp_id IN (SELECT smp_id FROM sample WHERE submission_id = $1)
        ORDER BY smp_id, seq_no
      SQL

      contact_rows = @conn.exec_params(<<~SQL, [ssub_id]).to_a
        SELECT email, first_name, last_name
        FROM   contact
        WHERE  submission_id = $1
        ORDER BY seq_no
      SQL

      Submission.new(
        ssub_id:          sub_row['submission_id'],
        submitter_id:     sub_row['submitter_id'],
        organization:     sub_row['organization'],
        organization_url: sub_row['organization_url'],
        comment:          sub_row['comment'],
        samples:      sample_rows.map {|s|
          Sample.new(
            smp_id:        s['smp_id'].to_i,
            accession:     s['accession_id'],
            sample_name:   s['sample_name'],
            package:       s['package'],
            package_group: s['package_group'],
            env_package:   s['env_package'],
            status_id:     s['status_id']&.to_i,
            attributes:    (attrs_by_smp[s['smp_id'].to_i] || []).map {|a|
              {'name' => a['attribute_name'], 'value' => a['attribute_value']}
            }
          )
        },
        contacts:     contact_rows.map {|c|
          Contact.new(email: c['email'], first: c['first_name'], last: c['last_name'])
        }
      )
    end
  end
end
