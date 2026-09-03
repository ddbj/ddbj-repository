# What a set's review link carries.
#
# Each accession is put on by the owner of the submission it belongs to,
# and only they can take it off again — which is why this is add-and-
# remove rather than a list to replace. Handing the whole list back would
# let one member wipe another's work off the link by saving a form they
# had open before it was added.
#
# Being able to read somebody's submission through a set has never been
# the right to hand it on (SubmissionSetInclusion says the same thing one
# floor down), and an anonymous link is as far on as it gets.
class SetSharedAccessionsController < ApplicationController
  include SetContents

  before_action :refuse_proxy!, only: %i[create destroy]
  before_action :load_set

  # Enough for the accessions of one paper pasted in a press, and far
  # less than a runaway client — the same reasoning, and the same number,
  # as putting submissions into a set. It bounds a request body, which is
  # not the same as bounding the link: what a link may carry has no
  # ceiling, and `all` below is how the two are reconciled.
  MAX_PER_CALL = 200

  # How many rows are written per statement when `all` resolves to more
  # than a screenful. Large enough that a hundred thousand samples is
  # twenty statements, small enough that none of them is a parameter list
  # the server has to hold whole.
  BATCH = 5_000

  # What the link carries, a page at a time — the same two steps and the
  # same caveat about short pages as the reviewer's own list, which is the
  # point: a member should be looking at exactly what a reviewer is.
  def index
    link = live_link

    @rows = link.shared_rows(paginate(link.shared_accessions).map(&:accession))
  end

  # Two forms, and the only difference is how the list is named.
  #
  # `accessions` is the ordinary press: the numbers written in a
  # manuscript, pasted in. Any of them may instead be a range —
  # `SAMD00000001-SAMD00000050` — which names whichever of the caller's
  # own accessions in the set fall inside it. That is what makes
  # "everything except the last three" something you write rather than
  # something you tick ninety-seven times, and it is why there is no
  # exclusion list on the wire: a range that stops short of them is the
  # exclusion.
  #
  # `all` is everything of theirs in the set, for the press that would
  # otherwise mean looking up both ends of a block to write a range that
  # spans all of it.
  #
  # Neither is a standing rule. Both resolve to rows at the moment they
  # are pressed, exactly as if every accession had been named one by one,
  # so a submission added to the set tomorrow is not on the link. Sharing
  # is something a person did, never something that happens.
  def create
    within_submission_set_membership(@set) do
      access = live_link

      # A dead link is not a place to put anything. It can still be
      # replaced — that is what the screen offers — but adding to it would
      # be sharing with somebody whose URL already 404s.
      refuse! 'This link has expired. Issue a new one first.' if access.expired?

      if params.key?(:all)
        # One accepted value, as the contract says. `all: false` would be
        # a third meaning nobody needs, and falling through to the named
        # path would answer it with "No accessions were named" — a
        # sentence about a key the caller did not send.
        refuse! 'The only accepted value for `all` is true.' unless params[:all] == true
        refuse! 'Name accessions or ask for all of them, not both.' if params.key?(:accessions)

        share_everything(access)
      else
        share_named(access)
      end
    end

    render :create
  end

  def destroy
    accession = params.expect(:accession)

    within_submission_set_membership(@set) do
      shared = live_link.shared_accessions.find_by!(accession:)
      rows   = @set.accession_rows([accession])

      # `any?` rather than the first row, so this asks the same question
      # `create` asks. One string can only name one row per table, but it
      # can name a row in more than one of the three, and "the first one
      # is mine" is not the rule.
      #
      # No rows at all is a row whose submission has left the set, and
      # nobody in the set can say whose it was. Letting anyone tidy that
      # is the only way it does not sit on the list for ever.
      if rows.any? { it.submission.user_id != current_user.id }
        forbid! 'Only the owner can take their own work off the link.'
      end

      shared.destroy!
    end

    head :no_content
  end

  private

  # The written form: numbers, ranges, or both. Refused whole if any of
  # them cannot go on — somebody pasting ten wants to hear which one is
  # wrong, not to find out later that the link carries nine.
  def share_named(access)
    numbers, ranges = split_selectors(named_accessions)

    added   = 0
    offered = 0

    if numbers.any?
      rows = @set.accession_rows(numbers)

      unknown = numbers - rows.map(&:accession)
      refuse! "Not in this set: #{unknown.join(', ')}." if unknown.any?

      theirs = rows.reject { it.submission.user_id == current_user.id }
      forbid! "Only the owner can share their own work: #{theirs.map(&:accession).join(', ')}." if theirs.any?

      offered += numbers.size
      added   += share(access, numbers)
    end

    if ranges.any?
      matched = Set.new
      named   = numbers.to_set

      range_added, range_offered = share_matching(access) {|accession|
        series, number = AccessionRange.split(accession)

        # Every range that covers it, not the first. Stopping at the first
        # would leave a second range that also covers it looking as though
        # it caught nothing, and the refusal below would then throw away
        # the whole press — including what the other ranges matched.
        hits = series ? ranges.select { it.include?(series, number) } : []

        matched.merge(hits)

        # Written twice — once as itself and once inside a range — is
        # still one accession, and counting it in both passes would
        # answer "1 added; 1 already on the link" for a single number.
        hits.any? && !named.include?(accession)
      }

      # A range that caught nothing is a mistake somebody wants to hear
      # about now: the usual cause is a prefix from the wrong database, or
      # a block that belongs to a colleague.
      empty = ranges - matched.to_a
      refuse! "Nothing of yours in this set falls in #{empty.join(', ')}." if empty.any?

      added   += range_added
      offered += range_offered
    end

    @added          = added
    @already_shared = offered - added
  end

  # The whole of the caller's own work in the set.
  def share_everything(access)
    @added, offered = share_matching(access) { true }
    @already_shared = offered - @added
  end

  # Everything of the caller's in the set that the block accepts.
  #
  # Nothing is checked against ownership because nothing here can fail it:
  # `owned_accessions` is their own work in this set and nobody else's,
  # which is the same question `share_named` asks one number at a time.
  #
  # Read in batches rather than plucked whole: a hundred thousand numbers
  # is not a thing to hold in memory to pick fifty out of.
  #
  # Each batch seeks past the last number of the one before it. OFFSET
  # would re-sort the whole union for every page, which on a submission
  # with a hundred thousand samples is twenty sorts of a hundred thousand
  # rows inside the set's lock.
  def share_matching(access)
    added   = 0
    offered = 0
    cursor  = nil

    loop do
      batch = @set.owned_accessions(current_user, after: cursor).limit(BATCH).pluck(:accession)
      break if batch.empty?

      cursor = batch.last

      numbers = batch.select {|accession| yield accession }
      next if numbers.empty?

      offered += numbers.size
      added   += share(access, numbers)
    end

    [added, offered]
  end

  # One statement per batch, and already-there is not a failure: ten
  # accessions where three are on the link is an ordinary press, and
  # refusing the lot — which is what the unique index does on its own —
  # would make somebody work out which three and paste the rest again.
  #
  # The count comes back from the insert rather than from a read before
  # it, so two members pressing at once are each told what they actually
  # added rather than both being told they added it.
  def share(access, numbers)
    ReviewerAccessAccession.insert_all(
      numbers.map {
        {reviewer_access_id: access.id, accession: it, added_by_id: current_user.id}
      },
      unique_by:         %i[reviewer_access_id accession],
      record_timestamps: true
    ).length
  end

  # The link, or a 404. The two writes below read it inside the lock and
  # nowhere else: any member may revoke, and one who does so between this
  # request arriving and its write would otherwise leave an insert
  # pointing at a row that has gone — a foreign-key violation rather than
  # an answer. `index` reads it unlocked on purpose; the worst a revoke
  # racing a read can do is answer 404 to a list nobody can see any more.
  def live_link
    @set.reviewer_access or raise ActiveRecord::RecordNotFound, "Couldn't find ReviewerAccess for SubmissionSet with 'id'=#{@set.id}"
  end

  # Read rather than `expect`ed: `expect` turns an empty list into a bare
  # 400 in Rails' own words, and "nothing was named" is a state a client
  # can be in and deserves a sentence.
  def named_accessions
    raw = params[:accessions]

    refuse! 'No accessions were named.' unless raw.is_a?(Array) && raw.any?

    numbers = clean_accessions(raw)

    refuse! 'No accessions were named.' if numbers.empty?

    numbers
  end

  # Which of the written tokens are accessions and which are ranges. A
  # token with a hyphen in it was meant as a range — no accession the
  # three databases issue carries one — so an unreadable one is reported
  # as a bad range rather than looked up as a number nobody has.
  def split_selectors(tokens)
    literals, written = tokens.partition { !AccessionRange.written_as_range?(it) }

    ranges = written.map {|token|
      AccessionRange.parse(token) or refuse!("Not an accession or a range: #{token}.")
    }

    [literals, ranges]
  end

  def clean_accessions(raw)
    # Before `uniq`, so the guard bounds the same thing the contract does
    # (`maxItems`) rather than whatever is left after the work is done.
    refuse! "Too many at once — #{MAX_PER_CALL} is the maximum." if raw.size > MAX_PER_CALL
    refuse! 'Accessions must be strings.' unless raw.all?(String)

    raw.map(&:strip).compact_blank.uniq
  end
end
