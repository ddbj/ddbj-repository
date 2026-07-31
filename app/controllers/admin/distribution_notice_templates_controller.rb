module Admin
  # Curator-editable subject / body for the release notice.
  #
  # No `edit`: the form lives on the Distribution notices screen's third
  # tab, next to a preview of what it produces. A separate page could show
  # the field but not the consequence.
  class DistributionNoticeTemplatesController < ApplicationController
    def update
      template = DistributionNotifierTemplate.instance

      if template.update(template_params)
        redirect_to admin_distribution_notices_path(tab: 'template'), notice: 'Template saved.'
      else
        # Re-render the tab it was edited on, carrying the invalid record
        # so the message lands next to the field that caused it.
        @template  = template
        @preview   = DistributionNoticePreview.new(template, [])
        @tab       = 'template'
        @due_count = DistributionNotifier.new.candidates.joins(:submission).distinct.count('submissions.user_id')

        render 'admin/distribution_notices/index', status: :unprocessable_content
      end
    end

    private

    def template_params
      params.expect(distribution_notifier_template: %i[subject body])
    end
  end
end
