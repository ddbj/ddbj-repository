class PublishBpLiveListJob < ApplicationJob
  # Same rationale as PublishBpXMLJob: nothing self-heals on retry.
  discard_on StandardError

  def perform
    output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('collab')

    LiveList::Exporter.new(
      output_dir:      output_dir,
      filename_prefix: 'bioproject',
      scope:           Project.where(status: LiveList::Exporter::LISTED_STATUSES).where.not(accession: nil)
    ).call
  end
end
