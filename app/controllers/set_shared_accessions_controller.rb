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

  before_action :refuse_proxy!
  before_action :load_set

  # Enough for the accessions of one paper pasted in a press, and far
  # less than a runaway client — the same reasoning, and the same number,
  # as putting submissions into a set.
  MAX_PER_CALL = 200

  # A list, always — one accession is a list of one. Refused whole if any
  # of them cannot go on: somebody pasting the accessions out of a
  # manuscript wants to hear which one is wrong, not to find out later
  # that the link carries nine of the ten.
  def create
    numbers = named_accessions

    within_submission_set_membership(@set) do
      access = live_link
      rows   = @set.accession_rows(numbers)

      # A dead link is not a place to put anything. It can still be
      # replaced — that is what the screen offers — but adding to it would
      # be sharing with somebody whose URL already 404s.
      refuse! 'This link has expired. Issue a new one first.' if access.expired?

      unknown = numbers - rows.map(&:accession)
      refuse! "Not in this set: #{unknown.join(', ')}." if unknown.any?

      theirs = rows.reject { it.submission.user_id == current_user.id }
      forbid! "Only the owner can share their own work: #{theirs.map(&:accession).join(', ')}." if theirs.any?

      # Already on the link is not a failure — ten accessions where three
      # are already there is an ordinary press, and refusing the lot,
      # which is what the unique index does, would make somebody work out
      # which three and paste the rest again.
      already = access.shared_accessions.where(accession: numbers).pluck(:accession)
      fresh   = numbers - already

      if access.shared_accessions.count + fresh.size > ReviewerAccess::MAX_SHARED
        refuse! "A review link carries at most #{ReviewerAccess::MAX_SHARED} accessions."
      end

      # One statement rather than one per row. Uniqueness is what `fresh`
      # was just filtered on, with the unique index behind it if two
      # presses race; there is nothing else to validate.
      if fresh.any?
        ReviewerAccessAccession.insert_all!(
          fresh.map {
            {reviewer_access_id: access.id, accession: it, added_by_id: current_user.id}
          },
          record_timestamps: true
        )
      end

      @added          = fresh.size
      @already_shared = already.size
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

  # Read inside the lock, and only there. Any member may revoke the link,
  # and one who does so between this request arriving and its write would
  # otherwise leave an insert pointing at a row that has gone — a
  # foreign-key violation rather than an answer.
  def live_link
    @set.reviewer_access or raise ActiveRecord::RecordNotFound, "Couldn't find ReviewerAccess for SubmissionSet with 'id'=#{@set.id}"
  end

  # Read rather than `expect`ed: `expect` turns an empty list into a bare
  # 400 in Rails' own words, and "nothing was named" is a state a client
  # can be in and deserves a sentence.
  def named_accessions
    raw = params[:accessions]

    refuse! 'No accessions were named.' unless raw.is_a?(Array) && raw.any?

    # Before `uniq`, so the guard bounds the same thing the contract does
    # (`maxItems`) rather than whatever is left after the work is done.
    refuse! "Too many at once — #{MAX_PER_CALL} is the maximum." if raw.size > MAX_PER_CALL
    refuse! 'Accessions must be strings.' unless raw.all?(String)

    numbers = raw.map(&:strip).compact_blank.uniq

    refuse! 'No accessions were named.' if numbers.empty?

    numbers
  end
end
