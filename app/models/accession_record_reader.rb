# Reading one accessioned row out of a record.
#
# Its own class rather than more of Submission: it is one job with state
# of its own, and it reaches the submission through five members — `db`,
# the two attachments a record can live in, the cache stamp, and the
# chain behind it. Nothing in `append_update!`, `prime_cache!` or
# `curation_rows` needs any of this, and none of it needs them.
#
# Where the record lives differs by database and the reading does not.
# BioProject and BioSample replay a patch chain and cache the result;
# ST.26 keeps what ApplySubmissionRequestJob wrote, as an attachment.
# Both are JSON in a blob, which is all the streaming needs.
class AccessionRecordReader
  # Shown where the record cannot be opened. Four, because there are four
  # ways and telling one as another sends somebody looking in the wrong
  # place — "not readable here yet" over a BioSample whose record is fine
  # blames the feature for a fact about the data.
  RECORD_NOT_READABLE_HERE = 'Records for this database are not readable here yet.'.freeze
  RECORD_UNREADABLE        = 'This record cannot be reconstructed from its history. DDBJ has been told.'.freeze
  RECORD_ABSENT            = 'This submission has no record yet.'.freeze
  RECORD_MISSING_ROW       = 'The record does not carry this row.'.freeze
  RECORD_LOST              = 'This record is stored but its file could not be read. DDBJ has been told.'.freeze

  # What the record says about one accessioned row, or why it cannot say.
  #
  # `subtree` is that row's own part of the record and nothing beside it:
  # a sample is a sample's fields, and the submitters in the record are a
  # fact about the submission. `unavailable_reason` is what the screen
  # shows instead — nil for a subtree that was found, and four different
  # sentences for the four ways there can be none, because "this database
  # is not readable here yet" and "your record does not carry this row"
  # are different things to be told.
  RecordSlice = Data.define(:subtree, :unavailable_reason)

  def initialize(submission)
    @submission = submission
  end

  # The part of the record one accession is: the project for a
  # BioProject, the one sample for a BioSample, the one entry for ST.26.
  def slice(row)
    case @submission.db
    when 'bioproject' then project_slice
    when 'biosample'  then biosample_slice(row)
    when 'st26'       then st26_slice(row)
    else
      # A database this does not know how to open. Unreachable while `db`
      # holds three values and all three are here; said rather than left
      # to fall through as "the record does not carry this row", which
      # would blame the data.
      RecordSlice.new(subtree: nil, unavailable_reason: RECORD_NOT_READABLE_HERE)
    end
  rescue Submission::MaterialisationFailed
    # A poisoned chain is a fact about this submission that the admin
    # screens exist to diagnose. Here it is a sentence, for the same
    # reason it is one there rather than a 500.
    RecordSlice.new(subtree: nil, unavailable_reason: RECORD_UNREADABLE)
  end

  private

  # Each of these answers with a slice rather than with a subtree and a
  # reason kept somewhere else: which branch ran and why it found nothing
  # are the same fact, and splitting them across a return value and an
  # instance variable made a caller's second call answer with the first
  # call's reason.
  def found(subtree) = RecordSlice.new(subtree:, unavailable_reason: subtree ? nil : RECORD_MISSING_ROW)

  def absent(reason = RECORD_ABSENT) = RecordSlice.new(subtree: nil, unavailable_reason: reason)

  # A BioProject's record is one project, so there is nothing to stream
  # past — the record is the project and a handful of fields beside it.
  def project_slice
    record = @submission.materialised_record or return absent

    found(record['project'])
  end

  # One sample, streamed out of the cache where there is a current one.
  #
  # Both halves of that condition, as `Submission#materialised_record` asks them.
  # The stamp is what says the blob is current: invalidation clears the
  # stamp and leaves the blob in place
  # (SubmissionUpdate#invalidate_submission_cache!), so a check on the
  # attachment alone reads an edited record as unedited — for ever,
  # because this path never re-primes.
  #
  # Cold means replaying the chain, which builds the whole record
  # whatever this does. The fast path is bounded; the slow path was
  # always going to cost.
  def biosample_slice(row)
    if @submission.cached_at_update_id.present? && @submission.cached_materialised_record.attached?
      begin
        return found(find_element(@submission.cached_materialised_record, 'samples') { it['alias'] == row.sample_name })
      rescue ActiveStorage::FileNotFoundError, Aws::S3::Errors::NoSuchKey => e
        # A cache whose object has gone is recoverable: the chain that
        # produced it is still there. Reported for the same reason
        # `read_cached_object` reports it — the replay below hides the
        # fault by fixing it.
        Rails.error.report e, context: {submission_id: @submission.id}
      end
    end

    record = @submission.materialised_record or return absent

    found(record['samples']&.find { it.is_a?(Hash) && it['alias'] == row.sample_name })
  end

  # One entry, streamed out of the record the apply wrote. Always
  # streamed: this is the database whose collections have no ceiling —
  # 27,080 entries in the largest submission here — and the one whose
  # elements carry a sequence, so building the array would be building
  # every base of every entry to read one of them.
  #
  # By `id`, which is what the typed row calls `entry_id`.
  def st26_slice(row)
    return absent unless @submission.ddbj_record.attached?

    found(find_element(@submission.ddbj_record, 'entries', parent: 'sequences') { it['id'] == row.entry_id })
  rescue ActiveStorage::FileNotFoundError, Aws::S3::Errors::NoSuchKey => e
    # Nothing behind this one to replay: for ST.26 the attachment IS the
    # record. So it is reported and said, rather than raised at a
    # submitter or answered with "no record yet", which would be false.
    Rails.error.report e, context: {submission_id: @submission.id}

    absent(RECORD_LOST)
  end

  # The first element of a named collection that matches, without
  # building the rest. A search, which is why it is named for what it
  # answers rather than for how.
  #
  # Stops at the first match: reading entry 1 of 27,080 should not build
  # the other 27,079. `throw` is what aborts an Oj stream — there is no
  # other way out of the parser's own loop.
  def find_element(attachment, key, parent: nil, &match)
    catch(:found) do
      attachment.open do |io|
        handler = DDBJRecord::StreamingParser::CollectionStreamHandler.new(key, parent:, result: false) {
          throw :found, it if it.is_a?(Hash) && match.call(it)
        }

        Oj.sc_parse(handler, io)
      end

      nil
    end
  end
end
