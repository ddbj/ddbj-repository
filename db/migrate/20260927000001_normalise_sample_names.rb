# A sample row names its sample as the record stores the alias.
#
# The BioSample importer wrote the alias as D-way spelled it, while the
# record stores it canonical (§2.2: runs of spaces collapsed, ends trimmed,
# NFC). Where the two differ, everything that finds a sample's record by
# its row — the TSV import, accession issuance, the public XML — missed it:
# the TSV import appended a second sample under the same alias, and an
# issued accession never reached the record. The importer now takes the
# stored form; this brings the rows written before into line.
#
# Only a name the normalisation could change is read: one with whitespace
# other than single inner ASCII spaces, or anything outside printable ASCII.
#
# The submissions it renames are printed: where a TSV import ran on one
# before, the record may hold a duplicate sample or lack an issued
# accession (`rake bio_sample:audit_sample_names` looks).
class NormaliseSampleNames < ActiveRecord::Migration[8.1]
  def up
    renamed = select_rows(<<~SQL).filter_map {|id, submission_id, name|
      SELECT id, submission_id, sample_name FROM samples WHERE sample_name ~ '(^\\s|\\s$|\\s\\s|[^ -~])'
    SQL
      normalised = Sample.normalise_name(name)

      next if normalised == name || normalised.empty?

      execute "UPDATE samples SET sample_name = #{quote(normalised)} WHERE id = #{Integer(id)}"
      submission_id
    }

    say "renamed samples of submissions #{renamed.uniq.sort.join(', ')}" if renamed.any?
  end

  def down
    # The spelling D-way used is still in D-way.
  end
end
