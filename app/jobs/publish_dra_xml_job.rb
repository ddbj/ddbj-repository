# See PublishBpXMLJob: a failure is on the run's row, and retrying would
# only add another.
class PublishDRAXMLJob < ApplicationJob
  discard_on StandardError

  def perform
    PublicXMLRun.exclusively db: 'dra', kind: 'public' do
      PublicXML::DRA::Exporter.new(output_dir: Pathname.new(Rails.application.config_for(:app).output_dir!).join('public', 'dra')).call
    end
  end
end
