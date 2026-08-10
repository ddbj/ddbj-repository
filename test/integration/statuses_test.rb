require 'test_helper'

# クライアントがバリデーションと適用の完了を待つ間、繰り返し叩くのがここ。
# 契約が守られていることを担保するテストが無かった。
class StatusesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show reports a request that has not failed' do
    get submission_request_status_path(submission_requests(:st26))

    assert_conform_schema 200

    body = response.parsed_body

    assert_nil body['error_code']
    assert_nil body['error_message']
  end

  # 失敗の理由は、文言ではなくコードで分岐できる形で出る。
  test 'show reports the code of a failed application' do
    # フィクスチャは ddbj_record を持たないので、モデルのバリデーションは通さない。
    submission_requests(:st26).update_columns(
      status:        SubmissionRequest.statuses.fetch('application_failed'),
      error_code:    'TRD_R0012',
      error_message: 'jpo_na: no numbers left after QX (wanted 3 more)'
    )

    get submission_request_status_path(submission_requests(:st26))

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 'application_failed', body['status']
    assert_equal 'TRD_R0012',          body['error_code']
    assert_not body['processing']
  end

  # status は current_user のスコープで引く。他人の request は 404。
  test 'show does not reach another user' do
    get submission_request_status_path(submission_requests(:st26)),
        headers: {'Authorization' => "Bearer #{users(:bob).api_key}"}

    assert_response :not_found
  end
end
