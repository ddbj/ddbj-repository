import { module, test } from 'qunit';
import { visit, click, fillIn } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];
type SetSummary = components['schemas']['SetSummary'];

const now = '2025-01-01T00:00:00.000Z';

const mine: SetSummary = {
  id: 7,
  name: 'Deep sea study',
  owner_uid: 'test-user',
  owned: true,
  created_at: now,
  member_count: 1,
  invited_count: 0,
  submission_count: 0,
  unread_message_count: 0,
};

function request(sets: SubmissionRequest['sets']): SubmissionRequest {
  return {
    id: 42,
    db: 'st26',
    status: 'validation_failed',
    error_code: null,
    error_message: null,
    created_at: now,
    closed_at: null,
    closable: true,
    sendable: false,
    send_blocked_reason: null,
    owned: true,
    owner_uid: 'test-user',
    processing: false,
    ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
    validation: null,
    submission: null,
    progress: {
      step: 'submitted',
      failed: false,
      closed: false,
      row_count: 0,
      accessioned_count: 0,
      hold_date: null,
    },
    unread_curator_message_count: 0,
    last_message_at: null,
    sets,
  };
}

module('Acceptance | putting a submission in a set', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  // The server answers 204 with no body. Anything else empty-bodied
  // reaches the fetch layer as a JSON parse error, which is how the first
  // version of this shipped broken — the row went in and the screen said
  // it had failed.
  test('adding it says so, and does not report a failure', async function (assert) {
    let added = false;
    let posted: unknown;

    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([mine]);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request(added ? [{ id: 7, name: 'Deep sea study' }] : []));
      }),

      http.post('/sets/{set_id}/submissions', async ({ request, response }) => {
        added = true;
        posted = await request.json();

        return response(200).json({ added: 1, already_in_set: 0 });
      }),
    );

    await visit('/requests/42');
    await fillIn('[data-test-sets] select', '7');
    await click('[data-test-sets] button');

    assert.true(added, 'the submission was posted to the set');

    // The body, not just that a request happened. Stubbing only the
    // response is how this shipped broken once: the endpoint moved to a
    // list and this caller kept sending the old shape, and the suite
    // stayed green over a panel that answered "No submissions were
    // named." to every press.
    assert.deepEqual(posted, { submission_request_ids: [42] });
    assert.dom('[data-test-sets] [data-test-error]').doesNotExist();
    assert.dom('[data-test-sets]').includesText('Deep sea study');
  });

  test('taking it back out', async function (assert) {
    let removed = false;

    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([mine]);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request(removed ? [] : [{ id: 7, name: 'Deep sea study' }]));
      }),

      http.delete('/sets/{set_id}/submissions/{submission_request_id}', ({ response }) => {
        removed = true;

        return response(204).empty();
      }),
    );

    await visit('/requests/42');
    await click('[aria-label="Take this submission out of Deep sea study"]');

    assert.true(removed, 'the submission was taken out');
    assert.dom('[data-test-sets]').includesText('not in any set');
  });

  // The panel used to render the list and nothing else here — no picker,
  // no way on — which reads as "a submission belongs to one set". It does
  // not.
  test('being in all of your sets still says another one is possible', async function (assert) {
    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([mine]);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request([{ id: 7, name: 'Deep sea study' }]));
      }),
    );

    await visit('/requests/42');

    assert.dom('[data-test-sets] select').doesNotExist();
    assert.dom('[data-test-sets]').includesText('can be in as many as it belongs in');
  });

  test('with a set it is not in yet, the picker says which kind of add this is', async function (assert) {
    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([mine, { ...mine, id: 8, name: 'Another study' }]);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request([{ id: 7, name: 'Deep sea study' }]));
      }),
    );

    await visit('/requests/42');

    assert.dom('[data-test-sets] label').hasText('Add to another set');
  });
});
