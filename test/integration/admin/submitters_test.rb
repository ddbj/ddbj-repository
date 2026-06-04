require 'test_helper'

class AdminSubmittersTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)

    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {
          'submitters' => [
            {
              'email'         => 'hanako@example.test',
              'first_name'    => 'Hanako',
              'last_name'     => 'Mishima',
              'organizations' => [{'name' => 'NIG', 'role' => 'owner', 'type' => 'institution'}]
            }
          ]
        }
      },
      actor:  'test-seed',
      source: :manual
    )
  end

  test 'PATCH update edits a submitter field and appends a SubmissionUpdate' do
    chain_before = @submission.updates.count

    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {email: 'hanako@new.example', first_name: 'Hanako', last_name: 'Mishima',
                    organizations: {'0' => {name: 'NIG', role: 'owner', type: 'institution'}}}
          }}

    assert_redirected_to admin_submission_path(@submission)
    @submission.reload
    assert_equal chain_before + 1, @submission.updates.count
    assert_equal 'hanako@new.example',
                 @submission.materialised_record.dig('submission', 'submitters', 0, 'email')
  end

  test 'PATCH update edits the organization for a submitter' do
    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {email: 'hanako@example.test', first_name: 'Hanako', last_name: 'Mishima',
                    organizations: {'0' => {name: 'NIG Updated', role: 'owner', type: 'institution', url: 'https://nig.ac.jp/'}}}
          }}

    assert_redirected_to admin_submission_path(@submission)
    org = @submission.reload.materialised_record.dig('submission', 'submitters', 0, 'organizations', 0)
    assert_equal 'NIG Updated',          org['name']
    assert_equal 'https://nig.ac.jp/',   org['url']
  end

  test 'PATCH update adds a new submitter via the trailing empty row' do
    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {email: 'hanako@example.test', first_name: 'Hanako', last_name: 'Mishima',
                    organizations: {'0' => {name: 'NIG', role: 'owner', type: 'institution'}}},
            '1' => {email: 'taro@example.test',   first_name: 'Taro',   last_name: 'Yamada',
                    organizations: {'0' => {name: 'NIG', role: 'owner', type: 'institution'}}}
          }}

    submitters = @submission.reload.materialised_record.dig('submission', 'submitters')
    assert_equal 2, submitters.size
    assert_equal 'Taro', submitters[1]['first_name']
  end

  test 'PATCH update with an all-blank row drops that submitter (== remove)' do
    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'submission'     => {
          'submitters' => [
            {'first_name' => 'A'},
            {'first_name' => 'B'}
          ]
        }
      },
      actor:  'test-seed-2',
      source: :manual
    )

    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {first_name: 'A'},
            '1' => {first_name: ''} # remove
          }}

    submitters = @submission.reload.materialised_record.dig('submission', 'submitters')
    assert_equal 1,   submitters.size
    assert_equal 'A', submitters[0]['first_name']
  end

  test 'PATCH update with all submitters blanked drops the submitters key entirely' do
    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {email: '', first_name: '', last_name: '',
                    organizations: {'0' => {name: '', role: '', type: '', url: ''}}}
          }}

    refute @submission.reload.materialised_record.dig('submission')&.key?('submitters'),
           'all-blank submitter set must drop the submitters key (matches Converter `.compact` idiom)'
  end

  test 'PATCH update with no change generates no patch (no-op)' do
    chain_before = @submission.updates.count

    patch admin_submission_submitters_path(@submission),
          params: {submitters: {
            '0' => {email: 'hanako@example.test', first_name: 'Hanako', last_name: 'Mishima',
                    organizations: {'0' => {name: 'NIG', role: 'owner', type: 'institution'}}}
          }}

    assert_match(/unchanged/, flash[:notice])
    assert_equal chain_before, @submission.reload.updates.count
  end

  test 'show page renders the submitters form when materialised record is present' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Submitters',                                  response.body
    assert_match admin_submission_submitters_path(@submission), response.body
    assert_match 'name="submitters[0][email]"',                 response.body
    assert_match 'name="submitters[0][organizations][0][name]"', response.body
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_submission_submitters_path(@submission),
          params: {submitters: {'0' => {first_name: 'X'}}}

    assert_response :forbidden
  end
end
