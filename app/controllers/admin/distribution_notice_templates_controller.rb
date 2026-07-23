module Admin
  # Curator-editable subject / body for the release notice.
  class DistributionNoticeTemplatesController < ApplicationController
    def edit
      @template = DistributionNotifierTemplate.instance
    end

    def update
      @template = DistributionNotifierTemplate.instance

      if @template.update(template_params)
        redirect_to edit_admin_distribution_notice_template_path, notice: 'Template saved.'
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def template_params
      params.expect(distribution_notifier_template: %i[subject body])
    end
  end
end
