module Admin
  # Curator-editable subject / body for the release notice.
  #
  # No `edit`: the form lives on the Distribution notices screen's third
  # tab, next to a preview of what it produces. A separate page could show
  # the field but not the consequence.
  #
  # Two buttons post here, distinguished by `commit`. They are one form
  # because they have to be: `button_to` renders a nested `<form>`, which
  # every HTML parser drops, so a second form inside this one would turn
  # its button into a submit for this action — and "send me a test" would
  # have published the edit to every submitter instead.
  class DistributionNoticeTemplatesController < ApplicationController
    def update
      params[:commit] == 'test' ? deliver_test : save
    end

    private

    # Rendered from what is in the form, not from what is saved. Checking
    # the text you are about to replace is not a check.
    #
    # Nothing is marked notified, nobody else is written to, and no
    # send-log row is left behind: a test is not a notice.
    def deliver_test
      if current_user.email.blank?
        return back_to_tab(alert: 'Your own account has no address on file, so there is nowhere to send a test.')
      end

      projects = DistributionNoticePreview.candidates
      return back_to_tab(alert: 'Nothing is due, so there is no real notice to render.') if projects.empty?

      DistributionNotifierMailer
        .with(user: current_user, projects:, draft: template_params.to_h)
        .release_notice
        .deliver_later

      back_to_tab(notice: "Test notice sent to #{current_user.email}.")
    end

    def save
      template = DistributionNotifierTemplate.instance

      if template.update(template_params)
        back_to_tab(notice: 'Template saved.')
      else
        # Re-render the tab it was edited on, carrying the invalid record
        # so the message lands next to the field that caused it — and the
        # preview the tab would otherwise have shown, rather than the
        # "nothing is due" empty state on a screen whose own badge says
        # otherwise.
        @template  = template
        @preview   = DistributionNoticePreview.for(template)
        @tab       = 'template'
        @due_count = DistributionNoticesController.due_count

        render 'admin/distribution_notices/index', status: :unprocessable_content
      end
    end

    def back_to_tab(**flash_message)
      redirect_to admin_distribution_notices_path(tab: 'template'), **flash_message
    end

    def template_params
      params.expect(distribution_notifier_template: %i[subject body])
    end
  end
end
