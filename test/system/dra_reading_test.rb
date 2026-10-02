require 'application_system_test_case'

# A DRA check whose metadata passed is held while its reads are read, which
# takes hours by design: the curator is told that, not shown it as a check
# that might be stuck.
class DRAReadingSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    @request = SubmissionRequest.new(user: users(:alice), db: 'dra', status: :validating).tap { it.save!(validate: false) }
    @request.create_validation!(progress: :running, raw_result: {'validity' => true, 'messages' => []}, created_at: 3.hours.ago)
  end

  test 'a check held for its reads says it is reading them, without looking stuck' do
    visit admin_submission_request_path(@request)

    assert_equal 200, page.status_code

    within '[data-test-validation-progress]' do
      assert_text 'reading the reads'
      assert_no_selector '.text-warning-emphasis'
    end

    assert_no_selector '[data-test-validation-progress].text-warning-emphasis'
  end
end
