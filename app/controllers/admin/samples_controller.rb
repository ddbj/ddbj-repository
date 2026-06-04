module Admin
  # Per-sample edit on BS submissions: status + assignee for one
  # specific Sample row. Complements the per-submission bulk-apply on
  # admin/submissions/show — bulk handles the common case ("advance
  # all samples together"), this edit handles the override ("set this
  # one sample to a different status"). After save, redirect back to
  # the BS submission show so the curator sees the change reflected
  # in the samples table.
  class SamplesController < ApplicationController
    def edit
      @sample = Sample.find(params[:id])
    end

    def update
      @sample = Sample.find(params[:id])

      attrs = sample_params.to_h.symbolize_keys

      # Empty status = "leave as-is"; "0" assignee = explicit unassign.
      attrs.delete(:status)         if attrs[:status].blank?
      attrs.delete(:assignee_id)    if attrs[:assignee_id].nil? || attrs[:assignee_id] == ''
      attrs[:assignee_id] = nil     if attrs[:assignee_id] == '0'

      if attrs.empty?
        return redirect_to edit_admin_sample_path(@sample),
                           alert: 'No changes specified (both fields left as-is).'
      end

      @sample.update!(attrs)

      redirect_to admin_submission_path(@sample.submission),
                  notice: "Sample ##{@sample.id} updated."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to edit_admin_sample_path(@sample),
                  alert: "Update failed: #{e.message}"
    end

    private

    def sample_params
      params.expect(sample: %i[status assignee_id])
    end
  end
end
