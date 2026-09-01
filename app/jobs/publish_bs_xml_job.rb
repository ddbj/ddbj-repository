class PublishBsXMLJob < ApplicationJob
  discard_on StandardError

  FILENAME = 'biosample.xml'

  def perform
    return if PublicXMLRun.where(db: 'biosample', kind: 'public', status: 'running').exists?

    output_dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join('public')

    PublicXML::Exporter.new(
      db:             'biosample',
      kind:           'public',
      output_dir:     output_dir,
      filename:       FILENAME,
      renderer_class: PublicXML::Bs::BioSampleRenderer,
      # By accession, as bsbatch ordered it (`ORDER BY a.accession_id`).
      # A consumer that diffs consecutive dumps, or stream-merges them by
      # accession, would otherwise read the whole file as changed on the
      # day we take over. The Exporter's caches are keyed by submission
      # and never evicted, so the order costs them nothing.
      scope:          Sample.status_public.includes(:submission).order(:accession)
    ).call
  end
end
