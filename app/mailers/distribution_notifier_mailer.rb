# Release-notice mail for the DistributionNotifier: one mail per submitter,
# listing their embargoed projects whose hold_date is approaching. Subject
# and body come from the curator-editable DistributionNotifierTemplate.
class DistributionNotifierMailer < ApplicationMailer
  def release_notice
    projects = Array(params[:projects])

    to = recipient_for(params[:user]) or return

    # `draft` lets the admin screen mail a copy of an *unsaved* edit to
    # the curator making it — saving is publishing, so a test rendered
    # from the saved text would be a test of the thing being replaced.
    # Passed as attributes rather than as the record: ActiveJob cannot
    # serialise an unsaved one, and this mail is always delivered later.
    @template = params[:draft] ? DistributionNotifierTemplate.new(params[:draft]) : DistributionNotifierTemplate.instance
    @notices  = projects.map { DistributionNotifierTemplate::Notice.for(it) }

    mail(to:, subject: @template.subject)
  end
end
