import { module, test } from 'qunit';
import { visit, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];

const now = '2025-01-01T00:00:00.000Z';

// A failed validation cannot be advanced — a corrected file arrives as a
// new request — so an abandoned attempt asks to be dealt with for ever,
// and the list floats exactly those to the top. Closing is the only end
// such a request can reach, and only the submitter knows it has come.
function failedRequest(attrs: Partial<SubmissionRequest> = {}): SubmissionRequest {
  return {
    id: 42,
    db: 'st26',
    status: 'validation_failed',
    error_message: null,
    created_at: now,
    closed_at: null,
    closable: true,
    processing: false,
    ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
    validation: null,
    submission: null,
    progress: {
      step: 'submitted',
      row_count: 0,
      failed: true,
      closed: false,
      accessioned_count: 0,
      hold_date: null,
    },
    unread_curator_message_count: 0,
    last_message_at: null,
    ...attrs,
  };
}

module('Acceptance | closing a request', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('a failed attempt can be put down and picked up again', async function (assert) {
    let closed = false;

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(failedRequest(closed ? { closed_at: now, closable: false } : {})),
      ),

      http.post('/submission_requests/{id}/closure', ({ response }) => {
        closed = true;

        return response(200).json(failedRequest({ closed_at: now, closable: false }));
      }),

      http.delete('/submission_requests/{id}/closure', ({ response }) => {
        closed = false;

        return response(200).json(failedRequest());
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );

    await visit('/requests/42');

    assert.dom('[data-test-state]').includesText('could not be processed');
    assert.dom('[data-test-close]').exists('a dead end offers a way to end it');

    await click('[data-test-close]');

    // Not deleted, and not silent about it: the request says what the
    // submitter decided, and offers the way back.
    assert.dom('[data-test-state]').includesText('You closed this request');
    assert.dom('[data-test-close]').doesNotExist();
    assert.dom('[data-test-reopen]').exists('closing undoes nothing, so it must be undoable');

    await click('[data-test-reopen]');

    assert.dom('[data-test-state]').includesText('could not be processed');
    assert.dom('[data-test-close]').exists();
  });
});
