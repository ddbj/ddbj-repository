import { module, test } from 'qunit';
import { visit, click, currentURL } from '@ember/test-helpers';
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
    error_code: null,
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
    sets: [],
    owned: true,
    owner_uid: 'test-user',
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

  // The one press that matches what almost everyone actually does. Left
  // as two, the corrected file goes up as a new request and the failed
  // one is only ever closed by somebody remembering to come back for it.
  test('closing and resubmitting lands on a fresh upload for the same database', async function (assert) {
    let closed = false;

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(failedRequest(closed ? { closed_at: now, closable: false } : {})),
      ),

      http.post('/submission_requests/{id}/closure', ({ response }) => {
        closed = true;

        return response(200).json(failedRequest({ closed_at: now, closable: false }));
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );

    await visit('/requests/42');
    await click('[data-test-close-and-resubmit]');

    assert.strictEqual(currentURL(), '/st26/requests/new', 'the database carries over');
    assert.true(closed, 'and the attempt it replaces is not left behind');
  });

  // Closing does not change the status, so a button gated on status
  // alone stays on offer and then fails against a server that will not
  // act on a closed request. The one-press path was a dead end on
  // exactly the requests it targets.
  test('a closed request offers nothing that acts on it', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(failedRequest({ closed_at: now, closable: false })),
      ),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );

    await visit('/requests/42');

    assert.dom('[data-test-close-and-resubmit]').doesNotExist();
    assert.dom('[data-test-close]').doesNotExist();
    assert.dom('[data-test-reopen]').exists('only the way back');
  });

  // "Apply" under "no longer waiting on you" is a contradiction before
  // it is a broken button — and the server refuses it either way.
  test('a closed request that had validated is not offered Apply', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          failedRequest({
            status: 'ready_to_apply',
            closed_at: now,
            closable: false,
            progress: {
              step: 'validated',
              row_count: 0,
              failed: false,
              closed: false,
              accessioned_count: 0,
              hold_date: null,
            },
          }),
        ),
      ),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );

    await visit('/requests/42');

    assert.dom('[data-test-state]').includesText('You closed this request');
    assert.dom('[data-test-state] button').hasText('Reopen', 'the only thing on offer');
  });

  // On a file that validated, the next step is Apply. A second primary
  // button offering a fresh upload would compete with it.
  test('a request that validated is not offered a corrected file', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) =>
        response(200).json(
          failedRequest({
            status: 'ready_to_apply',
            progress: {
              step: 'validated',
              row_count: 0,
              failed: false,
              closed: false,
              accessioned_count: 0,
              hold_date: null,
            },
          }),
        ),
      ),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),
    );

    await visit('/requests/42');

    assert.dom('[data-test-close-and-resubmit]').doesNotExist();
    assert.dom('[data-test-close]').exists('but it can still be put down');
  });
});
