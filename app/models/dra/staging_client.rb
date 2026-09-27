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

  Submission = Data.define(:sub_id, :submitter_id, :status, :accession, :hold_date, :dist_date, :release_date, :versions)

  # One saved state of the submission: when, and its documents' XML.
  Version = Data.define(:saved_at, :documents)

  Excluded = Data.define(:sub_id, :reason, :submitter_id, :status, :create_date)

  def initialize(**overrides)
    DataMigration::DwayDefaults.ensure_enabled!

    @conn = PG.connect(**DEFAULT_OPTIONS.merge(overrides))
    @conn.exec('SET search_path TO mass')

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

  # Submissions past the draft that have nothing to import: no valid
  # group, so no version was ever sent. In practice the ones cancelled
  # while still being written.
  def enumerate_excluded
    @conn.exec(<<~SQL).map {|row|
      SELECT s.sub_id, s.submitter_id, latest.status, s.create_date
      FROM (#{LATEST_STATUS}) latest
      JOIN submission s USING (sub_id)
      WHERE latest.status >= #{ACC_ISSUED}
        AND NOT EXISTS (SELECT 1 FROM submission_group g WHERE g.sub_id = s.sub_id AND g.valid)
      ORDER BY s.sub_id
    SQL
      Excluded.new(
        sub_id:       row['sub_id'],
        reason:       'no_versions',
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
      SELECT s.sub_id, s.submitter_id, s.hold_date, s.dist_date, s.release_date,
             (SELECT status FROM status_history h WHERE h.sub_id = s.sub_id ORDER BY date DESC LIMIT 1) AS status
      FROM submission s
      WHERE s.sub_id = $1::bigint
    SQL

    groups = @conn.exec_params(<<~SQL, [sub_id]).to_a
      SELECT grp_id, date FROM submission_group WHERE sub_id = $1::bigint AND valid ORDER BY serial_version
    SQL

    members = members_of(groups.map { it['grp_id'] })

    Submission.new(
      sub_id:       row['sub_id'],
      submitter_id: row['submitter_id'],
      status:       row['status'],
      accession:    accession_of(members[groups.last&.fetch('grp_id')]),
      hold_date:    row['hold_date'],
      dist_date:    row['dist_date'],
      release_date: row['release_date'],
      versions:     versions(groups, members)
    )
  end

  Meta   = Data.define(:meta_id, :acc_id, :kind, :saved_at)
  Member = Data.define(:acc_id, :acc_type, :acc_no)

  # Each moment something was saved, with the versions of the documents
  # that stood then (Metas, in KINDS order): for every object of the group
  # the moment belongs to, its latest version saved by then. A moment that
  # leaves the documents as they were is left out.
  #
  # `groups` are the valid ones, oldest first ({'grp_id', 'date'}),
  # `members` their objects by grp_id, `metas` every version past the
  # draft.
  def self.states(groups:, members:, metas:)
    by_acc = metas.group_by(&:acc_id)
    stood  = nil

    metas.map(&:saved_at).uniq.sort.filter_map {|saved_at|
      group = groups.find { it['date'] >= saved_at } || groups.last
      state = Array(members[group['grp_id']]).filter_map {|member|
        by_acc[member.acc_id]&.select { it.saved_at <= saved_at }&.max_by(&:saved_at)
      }.sort_by { [KINDS.index(it.kind) || KINDS.size, it.acc_id] }

      next if state.empty? || state.map(&:meta_id) == stood

      stood = state.map(&:meta_id)
      [saved_at, state]
    }
  end

  private

  LATEST_STATUS = <<~SQL.squish
    SELECT DISTINCT ON (sub_id) sub_id, status FROM status_history ORDER BY sub_id, date DESC
  SQL

  # {grp_id => [Member]}.
  def members_of(grp_ids)
    return {} if grp_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(grp_ids)]).group_by { it['grp_id'] }.transform_values {|rows|
      SELECT r.grp_id, a.acc_id, a.acc_type, a.acc_no
      FROM accession_relation r JOIN accession_entity a USING (acc_id)
      WHERE r.grp_id = ANY($1::bigint[])
    SQL
      rows.map { Member.new(acc_id: it['acc_id'], acc_type: it['acc_type'], acc_no: it['acc_no']) }
    }
  end

  def accession_of(members)
    member = members&.find { it.acc_type == 'DRA' } or return nil

    format('DRA%06d', member.acc_no)
  end

  def versions(groups, members)
    return [] if groups.empty?

    states   = self.class.states(groups:, members:, metas: metas_of(members.values.flatten.map(&:acc_id).uniq))
    contents = contents_of(states.flat_map { it.last.map(&:meta_id) }.uniq)

    states.map {|saved_at, state|
      Version.new(saved_at: saved_at.in_time_zone, documents: state.map { contents.fetch(it.meta_id) })
    }
  end

  # Every version past the draft (meta_version 0 is what was being written
  # before the first send), oldest first.
  def metas_of(acc_ids)
    return [] if acc_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(acc_ids)]).map {
      SELECT meta_id, acc_id, type, date FROM meta_entity
      WHERE acc_id = ANY($1::bigint[]) AND meta_version > 0
      ORDER BY acc_id, meta_version
    SQL
      Meta.new(meta_id: it['meta_id'], acc_id: it['acc_id'], kind: it['type'], saved_at: it['date'])
    }
  end

  def contents_of(meta_ids)
    return {} if meta_ids.empty?

    @conn.exec_params(<<~SQL, [PG::TextEncoder::Array.new.encode(meta_ids)]).to_h { [it['meta_id'], it['content']] }
      SELECT meta_id, content FROM meta_entity WHERE meta_id = ANY($1::bigint[])
    SQL
  end
end
