# Notifies the other side of a set's conversation. Replies happen in the
# web UI, as everywhere else here — these mails are notification only.
#
# The set-axis twin of SubmissionMessageMailer, with one difference worth
# knowing about: a message reaches **everyone in the set**, whoever wrote
# it. That is what "everyone here is party to this conversation" means
# for mail, and it is the thing that stops scaling first — a set with a
# dozen members is a mailing list. If that becomes a complaint, the fix
# is a per-member setting, not narrowing who can see the thread.
class SubmissionSetMessageMailer < ApplicationMailer
  # To the set: everyone on the roster except whoever wrote it.
  #
  # One action for both kinds of author. A member writing to the set is
  # writing to the people in it as much as to DDBJ — the screen says so —
  # and a thread where half the messages notify nobody would be a
  # conversation that only works in one direction.
  def notify_members
    @message = params[:message]
    @set     = @message.set
    @author  = @message.user

    recipients = @set.users.filter_map { recipient_for(it) unless it.id == @message.user_id }
    return if recipients.empty?

    # Bcc: the roster shows each member the address they were invited at,
    # which is not necessarily the address their account carries. Putting
    # the account addresses in To would hand every member something the
    # set never asked them for.
    mail(
      to:      recipient_for_self,
      bcc:     recipients,
      subject: "[DDBJ Repository] New message on the set “#{@set.name}”"
    )
  end

  # A member → the curators following this set. Nobody following means no
  # mail: the set reaches the queue on its own, which is how a thread
  # nobody has answered yet is found in the first place.
  def notify_curators
    @message = params[:message]
    @set     = @message.set

    recipients = @set.followers_to_notify(@message).filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(to: recipients, subject: "[DDBJ Repository] #{@message.user.uid} wrote on the set “#{@set.name}”")
  end

  # Something happened on a set you follow. Answering settles the thread
  # and takes it out of every curator's queue at the same moment, so
  # without this a curator following a set would never learn that a
  # colleague had answered.
  def followed_activity
    @message = params[:message]
    @set     = @message.set

    recipients = @set.followers_to_notify(@message).filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] #{@message.user.uid} replied on the set “#{@set.name}”"
    )
  end

  # Copied in by a colleague. A separate mail from the members', because
  # the audience and the ask are different: the set is being answered,
  # these curators are being shown something.
  #
  # It has to be a mail rather than only a subscription: a curator who
  # has just answered leaves nothing unanswered, so the queue would say
  # nothing about the set until a member writes back — which may be
  # never, and is not when they were asked to look.
  def copied_in
    @message = params[:message]
    @set     = @message.set

    recipients = @message.cc_users.filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] #{@message.user.uid} copied you in on the set “#{@set.name}”"
    )
  end

  private

  # A Bcc-only mail still needs somewhere to be addressed, and the
  # honest answer is us: this went to the set, and the copy in our own
  # mailbox is the record that it did.
  def recipient_for_self = self.class.default[:from]
end
