# What is about to be let go of, one mail per account.
class UnassignedFileMailer < ApplicationMailer
  def expiry_notice
    to = recipient_for(params[:user]) or return

    # Ids, not records: this is delivered later, and by then a file may have
    # been assigned or taken out. What is still there is what the mail is
    # about, and one query loads it with the blobs it names.
    @files = ActiveStorage::Attachment.where(id: params[:attachment_ids]).includes(:blob).order(:created_at, :id).to_a

    return if @files.empty?

    @until = @files.first.created_at + ExpireUnassignedFilesJob::KEEP_FOR

    mail(to:, subject: "Uploaded files waiting to be used will be removed on #{@until.to_date.iso8601}")
  end
end
