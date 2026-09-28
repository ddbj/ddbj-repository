# Applying a DDBJ Record v3 for a database curated here (BioProject,
# BioSample): the submission is made, the record becomes the first patch of
# its chain, and the rows it is curated as are made from it — no accession
# yet, status submission_accepted; issuing numbers is the curator's.
#
# The submission holds its own part of the record only. A record may carry
# projects and samples together (docs/v3-schema.md, "1 つの record の
# 範囲"), and each is registered by its own request; holding the other part
# too would leave two copies of the same samples, one of them never curated.
# The file as sent stays on the request, unchanged.
class SubmissionApply::V3Record
  # What every part keeps: the record's frame, and who is submitting.
  SHARED = %w[schema_version provenance submission].freeze

  def self.call(request) = new(request).call

  def initialize(request)
    @request = request
  end

  def call
    record = @request.ddbj_record.open { Oj.load(it.read, mode: :strict) }
    tree   = DDBJRecord::Canonicalizer.canonical_tree(own_part(record))

    Submission.transaction do
      submission = @request.create_submission!(db: @request.db, user: @request.user, canonical_version: DDBJRecord::Canonicalizer::NUMBER)

      update = SubmissionUpdate.create_with_patch!(
        submission:,
        patch_json:              Oj.dump([{'op' => 'add', 'path' => '', 'value' => tree}], mode: :strict),
        db:                      @request.db,
        status:                  :applied,
        actor:                   "submitter:#{@request.user.uid}",
        source:                  :submitted,
        patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
      )

      submission.prime_cache!(bytes: Oj.dump(tree, mode: :strict), update_id: update.id)

      build_rows submission, tree
    end
  end

  private

  # The database's own objects, and the relations that start from them.
  def own_part(record)
    part      = record.slice(*SHARED, self.class::OWN)
    relations = Array(record['relations']).select { it.is_a?(Hash) && it.dig('source', 'type') == self.class::KIND }

    part['relations'] = relations if relations.any?
    part
  end

  def build_rows(submission, tree)
    raise NotImplementedError
  end
end
