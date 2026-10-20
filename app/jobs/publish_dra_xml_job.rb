# See PublishBpXMLJob: a failure is on the run's row, and retrying would
# only add another.
#
# Not before D-way has handed over (DwayTakeover): the tree is D-way's,
# which its release still writes until then, and a status here that lags
# D-way's would take out what it has just published or put back what it
# has withdrawn.
class PublishDRAXMLJob < ApplicationJob
  discard_on StandardError

  def perform
    return unless DwayTakeover.done?

    PublicXMLRun.exclusively db: 'dra', kind: 'public' do
      PublicXML::DRA::Exporter.new(output_dir: Pathname.new(Rails.application.config_for(:app).output_dir!).join('public', 'dra')).call
    end
  end
end
