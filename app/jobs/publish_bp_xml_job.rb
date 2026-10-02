class PublishBpXMLJob < ApplicationJob
  # The Exporter already records the failure on the PublicXMLRun row; a
  # retry would just spawn a duplicate `failed` row on each attempt
  # without any chance of self-recovery (the failure modes are bad input
  # data or a missing output directory, neither of which heals with time).
  discard_on StandardError

  FILENAME = 'bioproject.xml'

  def perform
    PublicXMLRun.exclusively db: 'bioproject', kind: 'public' do
      output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('public')

      PublicXML::Exporter.new(
        db:             'bioproject',
        kind:           'public',
        output_dir:     output_dir,
        filename:       FILENAME,
        renderer_class: PublicXML::Bp::PackageRenderer,
        scope:          Project.status_public.includes(:submission).order(:id)
      ).call
    end
  end
end
