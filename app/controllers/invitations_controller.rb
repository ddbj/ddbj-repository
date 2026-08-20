# The page an invitation link lands on.
#
# Unauthenticated, and it has to be: the person holding the link may not
# have a DDBJ Account yet, and the page's job is to tell them what they
# are being invited to before it asks them to make one. What it
# discloses — a set name and who invited them — is what the mail they
# are holding already said.
class InvitationsController < ApplicationController
  skip_before_action :authenticate!, only: %i[show]

  # Every state of the link is answered rather than hidden. The holder is
  # the intended recipient, and "this has expired, ask them to send it
  # again" or "you have already used this" is the one thing that gets
  # them unstuck — unlike a reviewer share link, where a revoked link
  # must be indistinguishable from one that never existed.
  #
  # Which is why acceptance does not clear the token: see SubmissionSetMember.
  def show
    @member = SubmissionSetMember.find_by!(invitation_token: params.expect(:token).presence)
  end
end
