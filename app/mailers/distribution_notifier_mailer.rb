# Release-notice mail for the DistributionNotifier: one mail per submitter,
# listing their embargoed projects whose hold_date is approaching. Subject
# and body come from the curator-editable DistributionNotifierTemplate.
class DistributionNotifierMailer < ApplicationMailer
  def release_notice
    projects = Array(params[:projects])

    to = recipient_for(params[:user]) or return

    @template = DistributionNotifierTemplate.instance
    @notices  = projects.map { DistributionNotifierTemplate::Notice.for(it) }

    mail(to:, subject: @template.subject)
  end
end
