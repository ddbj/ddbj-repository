# Applying a DDBJ Record v3 for a database curated here (BioProject,
# BioSample, DRA): the submission is made, the record becomes the first patch
# of its chain, and the rows it is curated as are made from it — no accession
# yet, status submission_accepted; issuing numbers is the curator's.
#
# The submission holds its own part of the record only — the lists
# RecordIntake::OWN names for its database. A record may carry projects and
# samples together (docs/v3-schema.md, "1 つの record の 範囲"), and each is
# registered by its own request; holding the other part too would leave two
# copies of the same samples, one of them never curated. The file as sent
# stays on the request, unchanged.
class SubmissionApply::V3Record
  # What every part keeps: the record's frame, and who is submitting.
  SHARED = %w[schema_version provenance submission].freeze

  def self.call(request) = new(request).call

  def initialize(request)
    @request = request
  end

  # One commit, so a request that has its submission was applied — by a
  # run stopped before it said so — and running it again (RecoverKilledJobsJob)
  # has nothing to do.
  def call
    return if @request.submission

    # As sent, for what is said to the submitter about it: the kept tree is
    # canonical, and canonical order is not theirs.
    @sent = @request.ddbj_record.open { Oj.load(it.read, mode: :strict) }
    tree  = DDBJRecord::Canonicalizer.canonical_tree(own_part(@sent))
    bytes  = Oj.dump(tree, mode: :strict)

    Submission.transaction do
      submission = Submission.create!(db: @request.db, user: @request.user, canonical_version: DDBJRecord::Canonicalizer::NUMBER)

      # Said outright, as St26 says it: through autosave, a request whose
      # own validations fail would be left without it, and applied again.
      @request.update_columns submission_id: submission.id

      # Before the uploads: a failure here must not leave objects in
      # storage that the rollback cannot take back.
      build_rows submission, tree

      update = SubmissionUpdate.create_with_patch!(
        submission:,
        patch_json:              %([{"op":"add","path":"","value":#{bytes}}]),
        db:                      @request.db,
        status:                  :applied,
        actor:                   "submitter:#{@request.user.uid}",
        source:                  :submitted,
        patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
      )

      submission.prime_cache!(bytes:, update_id: update.id)
    end
  end

  private

  # The database's own objects, and the relations that start from them —
  # or from the record as a whole (no `source`) or its submission, which
  # are each part's as much as the frame is. A source that does not say
  # what kind of object it is could be either part's, so both keep it
  # rather than neither.
  def own_part(record)
    own   = RecordIntake::OWN.fetch(@request.db)
    kinds = [nil, 'submission', *own.map(&:singularize)]

    part      = record.slice(*SHARED, *own)
    relations = Array(record['relations']).select {|relation|
      next false unless relation.is_a?(Hash)

      source = relation['source']

      source.nil? || (source.is_a?(Hash) && kinds.include?(source['type']))
    }

    part['relations'] = relations if relations.any?
    part
  end

  def build_rows(submission, tree)
    raise NotImplementedError
  end
end
