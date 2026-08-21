# Notifies the other side of a set's conversation. Replies happen in the
# web UI, as everywhere else here — these mails are notification only.
#
# The set-axis twin of SubmissionMessageMailer, with one difference worth
# knowing about: a curator's message goes to **every member of the set**.
# That is what "everyone in the set is party to this conversation" means
# for mail, and it is the thing that stops scaling first — a set with a
# dozen members is a mailing list. If that becomes a complaint, the fix
# is a per-member setting, not narrowing who can see the thread.
class SubmissionSetMessageMailer < ApplicationMailer
  # Curator → the set.
  def notify_members
    @message = params[:message]
    @set     = @message.set
    @curator = @message.user

    recipients = @set.users.filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(to: recipients, subject: "[DDBJ Repository] New curator message on the set “#{@set.name}”")
  end

  # A member → the curators following this set. Nobody following means no
  # mail: the set reaches the queue on its own, which is how a thread
  # nobody has answered yet is found in the first place.
  def notify_curators
    @message = params[:message]
    @set     = @message.set

    recipients = @set.followers.filter_map { recipient_for(it) }
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
end
