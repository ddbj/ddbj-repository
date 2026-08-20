import { module, test } from 'qunit';
import { visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];

const now = '2025-01-01T00:00:00.000Z';

// What the server sends for a submission you can read through a set
// somebody else put it in: no conversation, nothing to press.
const shared: SubmissionRequest = {
  id: 42,
  db: 'bioproject',
  status: 'ready_to_apply',
  error_code: null,
  error_message: null,
  created_at: now,
  closed_at: null,
  closable: false,
  owned: false,
  owner_uid: 'colleague',
  processing: false,
  ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
  validation: {
    id: 1,
    progress: 'finished',
    created_at: now,
    finished_at: now,
    validity: 'invalid',

    details: [
      {
        entry_id: 'entry-1',
        severity: 'error',
        code: 'TRD_R0001',
        message: 'Something is wrong with entry-1.',
      },
    ],
  },
  submission: null,
  progress: {
    step: 'curating',
    failed: false,
    closed: false,
    row_count: 1,
    accessioned_count: 0,
    hold_date: null,
  },
  unread_curator_message_count: 0,
  last_message_at: null,
  sets: [{ id: 7, name: 'Deep sea study' }],
};

module('Acceptance | a submission shared into a set', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('is readable, but nothing on it is yours to press', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(shared);
      }),
    );

    await visit('/requests/42');

    // Where it has got to is the point of being able to see it at all.
    assert.dom().includesText('BioProject');

    // Sending, closing, the conversation, and the sharing controls all
    // belong to whoever submitted it.
    assert.dom('[data-test-send]').doesNotExist();
    assert.dom('[data-test-close]').doesNotExist();
    assert.dom('[data-test-messages]').doesNotExist();
    assert.dom().doesNotIncludeText('Share with a reviewer');

    // And nothing addresses them as the submitter. The panel is stated
    // about somebody; the validation report — which opens "this is still
    // your draft" — is not shown at all.
    assert.dom('[data-test-shared-state]').includesText("colleague's submission");
    assert.dom('[data-test-state]').doesNotExist();
    assert.dom().doesNotIncludeText('still your draft');
    assert.dom().doesNotIncludeText('ready to submit');
  });

  test('your own carries all of it', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json({ ...shared, owned: true, closable: true });
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),
    );

    await visit('/requests/42');

    assert.dom('[data-test-send]').exists();
    assert.dom('[data-test-close]').exists();
    assert.dom().includesText('Share with a reviewer');

    // The other half of the assertion above: the report IS shown to the
    // submitter, second person and all, so its absence there means
    // something.
    assert.dom('[data-test-state]').exists();
    assert.dom().includesText('still your draft');
  });
});
