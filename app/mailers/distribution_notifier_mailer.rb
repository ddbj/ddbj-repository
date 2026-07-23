# Release-notice mail for the DistributionNotifier: one mail per submitter,
# listing their embargoed projects whose hold_date is approaching.
class DistributionNotifierMailer < ApplicationMailer
  def release_notice
    @user     = params[:user]
    @projects = Array(params[:projects])

    # /web/requests/<id> per project — where the submitter can review the
    # request and, if the hold date needs changing, contact the curator via
    # its message thread.
    web_url = Rails.application.config_for(:app).web_url!
    @request_urls = @projects.to_h {|project|
      [project.id, URI.join(web_url, "/web/requests/#{project.submission.request.id}").to_s]
    }

    mail(
      to:      user_email_or_placeholder(@user),
      subject: '[DDBJ Repository] Your data will be released soon'
    )
  end
end
