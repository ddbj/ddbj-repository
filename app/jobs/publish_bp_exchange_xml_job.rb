class PublishBpExchangeXMLJob < ApplicationJob
  # Same rationale as PublishBpXMLJob: the Exporter records the failure on
  # the PublicXMLRun row, and the failure modes (bad data / missing output
  # dir) don't heal on retry.
  discard_on StandardError

  FILENAME = 'bioproject.xml'

  def perform
    # Soft concurrency guard against a mid-run duplicate (see PublishBpXMLJob).
    return if PublicXMLRun.where(db: 'bioproject', kind: 'exchange', status: 'running').exists?

    # Delta window: everything released / re-released since the previous
    # EXCHANGE run counts as eAdded / eUpdated. `exec_date` is this run's
    # cut-off. Anchoring on the previous exchange run (not the public run)
    # mirrors legacy bpbatch's independent lastRun_Collab marker — see
    # PublicXMLRun's class comment.
    last_run  = PublicXMLRun.previous_run(db: 'bioproject', kind: 'exchange')&.started_at
    exec_date = Time.current

    output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('exchange')

    PublicXML::Exporter.new(
      db:               'bioproject',
      kind:             'exchange',
      output_dir:       output_dir,
      filename:         FILENAME,
      renderer_class:   PublicXML::Bp::ExchangePackageRenderer,
      renderer_options: {last_run:, exec_date:},
      scope:            Project.status_public.includes(:submission).order(:id)
    ).call
  end
end
