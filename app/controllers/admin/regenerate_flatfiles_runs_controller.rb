module Admin
  # A regeneration run, on its own page and inside the frame the tool
  # screen polls. Same partial either way: what a run says about itself
  # should not depend on where it is being read.
  class RegenerateFlatfilesRunsController < ApplicationController
    before_action :set_run

    def show; end

    # Every failure, as text — the list a curator pastes into a ticket or
    # works through offline. Rendered from the stored rows rather than
    # from the submissions, so it matches what the screen showed.
    def failures
      body = @run.failures.map { "#{it.display_label}\t#{it.message}" }.join("\n")

      send_data "#{body}\n",
                filename: "regenerate-flatfiles-#{@run.id}-failures.txt",
                type:     'text/plain'
    end

    private

    def set_run
      @run = RegenerateFlatfilesRun.find(params[:id])
    end
  end
end
