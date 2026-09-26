module Admin
  # Curator edit to v3 `/projects/0/title` + `/projects/0/description` on a BP
  # submission. The v3 record is the source of truth (the BP Importer's
  # `Project.update!(title: record.dig('projects', 0, 'title'))` already
  # treats Project.title as a denormalised cache); this controller goes
  # through the patch chain via Submission#append_update! AND mirrors
  # the record back to the Project typed columns
  # (Submission#sync_projections!) so the admin index display stays
  # consistent without waiting for a re-import.
  # (Description has no typed column — Project.description doesn't
  # exist; mirror would be a no-op.)
  class ProjectRecordsController < ApplicationController
    EDITABLE_FIELDS = %w[title description].freeze

    def update
      submission = Submission.find(params[:submission_id])
      project    = submission.project or raise ActiveRecord::RecordNotFound

      raw  = record_params

      new_record = patched_record(submission, raw)

      result = submission.append_update!(
        new_record,
        actor:  current_actor,
        source: :manual
      )

      # Mirror the record onto the typed columns, from the record itself so
      # the two cannot differ (both writes are idempotent).
      submission.sync_projections!(new_record) if result

      participate!(submission.request) if result

      message = result ? "Project record saved (chain length now #{submission.updates.count})." \
                       : 'Project record unchanged — no patch generated.'

      redirect_to admin_submission_request_path(submission.request), notice: message
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_request_path(submission.request),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    def record_params
      params.expect(project_record: EDITABLE_FIELDS).to_h
    end

    # Apply each editable field by `.presence`-filtering and either
    # writing it onto `/projects/0/<field>` or dropping the key entirely.
    # Matches the Converter's `.compact` idiom so a blank input doesn't
    # round-trip as `""` in the v3 record.
    def patched_record(submission, raw)
      record  = submission.materialised_record.deep_dup
      project = BioProject.record_project!(record)

      EDITABLE_FIELDS.each do |f|
        next unless raw.key?(f)

        val = raw[f].to_s.presence
        if val
          project[f] = val
        else
          project.delete(f)
        end
      end

      record.delete('projects') if project.empty?
      record
    end
  end
end
