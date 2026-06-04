module Admin
  # Curator edit to v3 `/project/title` + `/project/description` on a BP
  # submission. The v3 record is the source of truth (the BP Importer's
  # `Project.update!(title: record.dig('project', 'title'))` already
  # treats Project.title as a denormalised cache); this controller goes
  # through the patch chain via Submission#append_update! AND mirrors
  # the title back to the Project.title typed column so the admin
  # index display stays consistent without waiting for a re-import.
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
        actor:  "admin:#{current_user.uid}",
        source: :manual
      )

      # Mirror title to the typed column inside the same transaction
      # boundary as append_update! (separate transaction is fine — both
      # writes are idempotent: identical title is a no-op on either
      # side).
      project.update!(title: raw['title'].to_s.strip.presence) if result && raw.key?('title')

      message = result ? "Project record saved (chain length now #{submission.updates.count})." \
                       : 'Project record unchanged — no patch generated.'

      redirect_to admin_submission_path(submission), notice: message
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_path(submission),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    def record_params
      params.expect(project_record: EDITABLE_FIELDS).to_h
    end

    # Apply each editable field by `.presence`-filtering and either
    # writing it onto `/project/<field>` or dropping the key entirely.
    # Matches the Converter's `.compact` idiom so a blank input doesn't
    # round-trip as `""` in the v3 record.
    def patched_record(submission, raw)
      record  = submission.materialised_record.deep_dup
      project = record['project'] ||= {}

      EDITABLE_FIELDS.each do |f|
        next unless raw.key?(f)

        val = raw[f].to_s.presence
        if val
          project[f] = val
        else
          project.delete(f)
        end
      end

      record.delete('project') if project.empty?
      record
    end
  end
end
