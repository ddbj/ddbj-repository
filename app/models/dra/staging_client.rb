# frozen_string_literal: true

require 'pg'

# Read-only connection to D-way's DRA database (drmdb), for the importer.
#
# A DRA submission there is a set of SRA XML documents, one per object
# (the submission itself, its studies, samples, experiments, runs and
# analyses), each kept in every version it was saved in (`meta_entity`).
# Which objects make up the submission at a given moment is a group
# (`submission_group` → `accession_relation`), written each time the
# submitter sends it.
#
# The history this reads is one version per moment something was saved:
# a save writes every object's version under one timestamp, and the group
# recording the send follows seconds later. So the objects of a moment are
# the first valid group written at or after it — or the last group, for
# what a curator changed after the final send, which writes versions and
# no group.
#
# Only what went further than a draft is read: a submission whose latest
# status is ACC_ISSUED (500) or later. 500 is not a waiting room — a
# curator has issued the accessions and the batch is converting the reads,
# which moves it to 700 on its own.
class DRA::StagingClient
  DEFAULT_OPTIONS = DataMigration::DwayDefaults.options(dbname: 'drmdb').freeze

  # dracommon's SubmissionStatus.
  ACC_ISSUED = 500

  # The document kinds in the order a record is built from them: the
  # submission first, and each kind before those that refer to it.
  KINDS = %w[submission study sample experiment run analysis].freeze

  Submission = Data.define(:sub_id, :submitter_id, :status, :status_changed_at, :accession, :hold_date, :dist_date, :release_date, :versions)

  # One saved state of the submission: when, its documents' XML, and a
  # digest of which versions of them these are — what tells this state
  # from another saved in the same instant.
  Version = Data.define(:saved_at, :documents, :digest)

  Excluded = Data.define(:sub_id, :reason, :submitter_id, :status, :create_date)

  def initialize(**overrides)
    DataMigration::DwayDefaults.ensure_enabled!

    @conn = DataMigration::DwayDefaults.connect(DEFAULT_OPTIONS.merge(overrides))

    # Timestamps compared as times, not as their text: a save's moment and
    # the group after it differ by seconds, and the text's fractional part
    # comes and goes.
    @conn.type_map_for_results = PG::BasicTypeMapForResults.new(@conn)
  end

  def close
    @conn.close
  end

  def source_fingerprint
    DataMigration::DwayDefaults.fingerprint(@conn, tables: %w[mass.submission mass.meta_entity])
  end

  # The sub_ids of every submission past the draft, ordered for a resumable
  # sweep. `after` is the last one a previous pass finished.
  def submission_ids(limit: nil, after: nil)
    sql    = +"SELECT sub_id FROM (#{LATEST_STATUS}) latest WHERE status >= #{ACC_ISSUED}"
    params = []

    if after
      sql << ' AND sub_id > $1::bigint'
      params << after
    end

    sql << ' ORDER BY sub_id'
    sql << " LIMIT #{limit.to_i}" if limit

    @conn.exec_params(sql, params).column_values(0)
  end

  # Submissions past the draft that have nothing to import:
  #
  #   - no_versions: nothing was ever sent — no valid group, or none of its
  #     objects saved past the draft. In practice cancelled while still
  #     being written.
  #   - no_accession: sent, but cancelled before a curator issued the
  #     accessions — nothing in it was ever numbered.
  def enumerate_excluded
    @conn.exec(<<~SQL).map {|row|
      WITH classified AS (
        SELECT s.sub_id, s.submitter_id, latest.status, s.create_date,
               NOT EXISTS (
                 SELECT 1 FROM submission_group g
                 JOIN accession_relation r USING (grp_id)
                 JOIN meta_entity m ON m.acc_id = r.acc_id AND m.meta_version > 0
                 WHERE g.sub_id = s.sub_id AND g.valid
               ) AS unsent,
               NOT EXISTS (
                 SELECT 1 FROM accession_relation r JOIN accession_entity a USING (acc_id)
                 WHERE r.grp_id = last.grp_id AND a.acc_type IN (#{SUBMISSION_TYPES.map { "'#{it}'" }.join(', ')}) AND a.acc_no IS NOT NULL
               ) AS unnumbered
        FROM (#{LATEST_STATUS}) latest
        JOIN submission s USING (sub_id)
        LEFT JOIN LATERAL (
          SELECT grp_id FROM submission_group g WHERE g.sub_id = s.sub_id AND g.valid ORDER BY serial_version DESC LIMIT 1
        ) last ON true
        WHERE latest.status >= #{ACC_ISSUED}
      )
      SELECT sub_id, submitter_id, status, create_date,
             CASE WHEN unsent THEN 'no_versions' ELSE 'no_accession' END AS reason
      FROM classified
      WHERE unsent OR unnumbered
      ORDER BY sub_id
    SQL
      Excluded.new(
        sub_id:       row['sub_id'],
        reason:       row['reason'],
        submitter_id: row['submitter_id'],
        status:       row['status'],
        create_date:  row['create_date']
      )
    }
  end

  # The submission with its history, or nil for a sub_id drmdb does not
  # have. `versions` is empty for one that was never sent.
  def fetch(sub_id)
    row = @conn.exec_params(<<~SQL, [sub_id]).first or return nil
      SELECT s.sub_id, s.submitter_id, s.hold_date, s.dist_date, s.release_date, h.status, h.date AS status_changed_at
      FROM submission s
      LEFT JOIN LATERAL (
        SELECT status, date FROM status_history WHERE sub_id = s.sub_id ORDER BY date DESC, id DESC LIMIT 1
      ) h ON true
      WHERE s.sub_id = $1::bigint
    SQL

    groups = @conn.exec_params(<<~SQL, [sub_id]).to_a
      SELECT grp_id, date FROM submission_group WHERE sub_id = $1::bigint AND valid ORDER BY serial_version
    SQL

    members = members_of(groups.map { it['grp_id'] })

    Submission.new(
      sub_id:            row['sub_id'],
      submitter_id:      row['submitter_id'],
      status:            row['status'],
      status_changed_at: row['status_changed_at']&.in_time_zone,
      accession:         accession_of(members[groups.last&.fetch('grp_id')]),
      hold_date:         row['hold_date'],
      dist_date:         row['dist_date'],
      release_date:      row['release_date'],
      versions:          versions(groups, members)
    )
  end

  Meta   = Data.define(:meta_id, :acc_id, :meta_version, :kind, :saved_at)
  Member = Data.define(:acc_id, :acc_type, :acc_no, :deleted)

  # Each moment something was saved, with the versions of the documents
  # that stood then (Metas, in KINDS order): for every object of the group
  # the moment belongs to, its latest version saved by then. A moment that
  # leaves the documents as they were is left out.
  #
  # An object deleted after the last send stays in that group, marked
  # deleted, with no date for when; it is left out of what was saved after
  # the send, which is as near as the history can place it.
  #
  # `groups` are the valid ones, oldest first ({'grp_id', 'date'}),
  # `members` their objects by grp_id, `metas` every version past the
  # draft.
  def self.states(groups:, members:, metas:)
    stood   = nil
    current = {}

    # Walked in the order they were saved, holding each object's highest
    # version so far — by number, not by time: a handful of versions are
    # dated before the one they follow.
    metas.sort_by { [it.saved_at, it.meta_version] }.chunk_while { _1.saved_at == _2.saved_at }.filter_map {|saved|
      saved.each do |meta|
        current[meta.acc_id] = meta if (current[meta.acc_id]&.meta_version || -1) < meta.meta_version
      end

      saved_at = saved.first.saved_at
      group    = groups.find { it['date'] >= saved_at }
      stand    = group ? Array(members[group['grp_id']]) : Array(members[groups.last['grp_id']]).reject(&:deleted)
      state    = stand.filter_map { current[it.acc_id] }.sort_by { [KINDS.index(it.kind) || KINDS.size, it.acc_id] }

      next if state.empty? || state.map(&:meta_id) == stood

      stood = state.map(&:meta_id)
      [saved_at, state]
    }
  end

  private

  # The id breaks a tie between two statuses written in one second, here and
  # in #fetch.
  LATEST_STATUS = <<~SQL.squish
    SELECT DISTINCT ON (sub_id) sub_id, status FROM status_history ORDER BY sub_id, date DESC, id DESC
  SQL

  SUBMISSION_TYPES = %w[DRA SRA].freeze

  # {grp_id => [Member]}.
  def members_of(grp_ids)
    return {} if grp_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(grp_ids)]).group_by { it['grp_id'] }.transform_values {|rows|
      SELECT r.grp_id, a.acc_id, a.acc_type, a.acc_no, a.is_delete
      FROM accession_relation r JOIN accession_entity a USING (acc_id)
      WHERE r.grp_id = ANY($1::bigint[])
    SQL
      rows.map { Member.new(acc_id: it['acc_id'], acc_type: it['acc_type'], acc_no: it['acc_no'], deleted: it['is_delete']) }
    }
  end

  # DRA000072 — or SRA002058, for the 27 early submissions D-way numbers
  # under SRA. Nil where the number was never issued: a submission cancelled
  # after it was sent but before a curator issued its accessions.
  def accession_of(members)
    member = members&.find { SUBMISSION_TYPES.include?(it.acc_type) && it.acc_no } or return nil

    format('%s%06d', member.acc_type, member.acc_no)
  end

  def versions(groups, members)
    return [] if groups.empty?

    states   = self.class.states(groups:, members:, metas: metas_of(members.values.flatten.map(&:acc_id).uniq))
    contents = contents_of(states.flat_map { it.last.map(&:meta_id) }.uniq)

    states.map {|saved_at, state|
      Version.new(
        saved_at:  saved_at.in_time_zone,
        documents: state.map { contents.fetch(it.meta_id) },
        digest:    Digest::MD5.hexdigest(state.map(&:meta_id).join(','))
      )
    }
  end

  # Every version past the draft (meta_version 0 is what was being written
  # before the first send).
  def metas_of(acc_ids)
    return [] if acc_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(acc_ids)]).map {
      SELECT meta_id, acc_id, meta_version, type, date FROM meta_entity
      WHERE acc_id = ANY($1::bigint[]) AND meta_version > 0
    SQL
      Meta.new(meta_id: it['meta_id'], acc_id: it['acc_id'], meta_version: it['meta_version'], kind: it['type'], saved_at: it['date'])
    }
  end

  def contents_of(meta_ids)
    return {} if meta_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(meta_ids)]).to_h { [it['meta_id'], it['content']] }
      SELECT meta_id, content FROM meta_entity WHERE meta_id = ANY($1::bigint[])
    SQL
  end
end
