class PublishBpXMLJob < ApplicationJob
  # The Exporter already records the failure on the PublicXMLRun row; a
  # retry would just spawn a duplicate `failed` row on each attempt
  # without any chance of self-recovery (the failure modes are bad input
  # data or a missing output directory, neither of which heals with time).
  discard_on StandardError

  FILENAME = 'public_package_set.xml'

  def perform
    # Soft concurrency guard — if an operator triggers `perform_now`
    # while the recurring fire is mid-run we'd otherwise race the file
    # rename and leave the loser stuck in `running`. Race-free coverage
    # would need an advisory lock; this guard catches the common case
    # without dragging Postgres locks in.
    return if PublicXMLRun.where(db: 'bioproject', kind: 'public', status: 'running').exists?

    output_dir = Rails.application.config_for(:app).public_xml_bp_dir!

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
