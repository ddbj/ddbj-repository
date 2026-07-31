require 'test_helper'

# Two admin screens put a second submit button inside an existing form via
# `formaction`, so both buttons post the same checkbox selection to
# different endpoints.
#
# That only works while the form and the button agree on the HTTP method.
# A `method: :patch` form emits a hidden `_method` field, and
# Rack::MethodOverride (mounted for /admin) applies it to EVERY submit —
# including one carrying `formmethod="post"`. The accession routes are
# POST-only, so the button 404s. These pin the shape that avoids it.
class AdminFormMethodsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:bob) }

  # Scoped to the bulk form itself — the layout's logout `button_to` is a
  # self-contained form and may legitimately carry an override.
  def assert_no_method_override(action)
    form = css_select("form[action^='#{action}']").first

    assert form, "expected a form posting to #{action}"
    assert_empty form.css("input[name='_method']"),
                 'a hidden _method is applied to every submit, including the ' \
                 "accession button's formaction, whose route is POST-only"
  end

  test 'the request list form carries no method override' do
    get admin_submission_requests_path

    assert_response :ok
    assert_no_method_override(bulk_update_admin_submissions_path)
  end

  test 'the samples bulk form carries no method override' do
    get samples_admin_submission_request_path(submission_requests(:biosample))

    assert_response :ok
    assert_no_method_override(bulk_update_samples_admin_submission_path(submissions(:biosample)))
  end

  # The endpoints both forms reach must accept the method those forms use.
  test 'every endpoint the shared bulk buttons target accepts POST' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    [
      bulk_update_admin_submissions_path,
      bulk_issue_accessions_admin_submissions_path,
      bulk_update_samples_admin_submission_path(submissions(:biosample)),
      admin_submission_accession_path(submission)
    ].each do |path|
      post path

      refute_equal 404, response.status, "#{path} must be reachable by POST"
    end
  end
end
