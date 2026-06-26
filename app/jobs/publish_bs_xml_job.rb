class PublishBsXMLJob < ApplicationJob
  discard_on StandardError

  FILENAME = 'public_biosample_set.xml'

  def perform
    return if PublicXMLRun.where(db: 'biosample', kind: 'public', status: 'running').exists?

    output_dir = Rails.application.config_for(:app).public_xml_bs_dir!

    PublicXML::Exporter.new(
      db:             'biosample',
      kind:           'public',
      output_dir:     output_dir,
      filename:       FILENAME,
      renderer_class: PublicXML::Bs::BioSampleRenderer,
      # Group by submission so v3_by_submission cache hits stay warm and
      # the alias index is built once per submission (see Exporter#call).
      scope:          Sample.status_public.includes(:submission).order(:submission_id, :id)
    ).call
  end
end
