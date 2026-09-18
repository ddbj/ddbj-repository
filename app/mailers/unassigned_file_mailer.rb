# What is about to be let go of, one mail per account.
class UnassignedFileMailer < ApplicationMailer
  def expiry_notice
    to = recipient_for(params[:user]) or return

    @files = Array(params[:attachments]).sort_by(&:created_at)
    @until = @files.first.created_at + ExpireUnassignedFilesJob::KEEP_FOR

    mail(to:, subject: "Uploaded files waiting to be used will be removed on #{@until.to_date.iso8601}")
  end
end
