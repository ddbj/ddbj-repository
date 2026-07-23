# Release-notice mail for the DistributionNotifier: one mail per submitter,
# listing their embargoed projects whose hold_date is approaching. Subject
# and body come from the curator-editable DistributionNotifierTemplate.
class DistributionNotifierMailer < ApplicationMailer
  def release_notice
    @user     = params[:user]
    @projects = Array(params[:projects])

    template = DistributionNotifierTemplate.instance
    @body    = template.render_body(projects: @projects, web_url: Rails.application.config_for(:app).web_url!)

    mail(to: user_email_or_placeholder(@user), subject: template.subject)
  end
end
