module Legacy
  # The db-scoped submission request endpoints, kept working while the
  # clients move to the flat ones. See the deprecated block in
  # config/routes.rb for why they still exist and when to delete them.
  #
  # A subclass rather than a branch in the controller itself, so the
  # whole deprecation is one file and one routing block: nothing in the
  # endpoint that is staying has to know this ever happened.
  class SubmissionRequestsController < ::SubmissionRequestsController
    before_action :adopt_path_db, only: :create

    # The responses belong to the endpoint that is staying — this class
    # adds a rule, not a representation. Left alone, the subclass
    # introduces a `legacy/submission_requests` view prefix and the
    # partials the templates render are looked for under it.
    def self._prefixes = superclass._prefixes

    private

    # Under the old routes the database was the path, so no client sends
    # it in the body — and `create` now reads it from there. Without this
    # the request 400s on a missing parameter, which is the one failure a
    # compatibility route exists to prevent.
    #
    # `||=`, so a body that does name a database keeps saying what it
    # says; the two disagreeing is a client bug, and quietly rewriting
    # the payload would hide it.
    def adopt_path_db
      body = params[:submission_request]

      body[:db] ||= params[:db] if body.is_a?(ActionController::Parameters)
    end
  end
end
