import { module, test } from 'qunit';
import { visit, click, triggerEvent, currentURL, waitUntil } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];
type SubmissionUpdate = components['schemas']['SubmissionUpdate'];

const now = '2025-01-01T00:00:00.000Z';

const submission: Submission = {
  id: 1,
  created_at: now,
  updated_at: now,

  ddbj_record: {
    filename: 'original.json',
    url: 'http://example.com/original.json',
  },

  accessions: [
    {
      number: 'ACC001',
      entry_id: 'entry-1',
      version: 1,
      last_updated_at: now,
    },
  ],

  updates: [],
};

module('Acceptance | submission update', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('create and apply', async function (assert) {
    // --- Submission detail page ---

    worker.use(
      http.get('/submissions/{id}', ({ response }) => {
        return response(200).json(submission);
      }),
    );

    await visit('/submissions/1');

    assert.strictEqual(currentURL(), '/submissions/1');
    assert.dom('h1').hasText('Submission-1');

    // --- Navigate to new update page ---

    await click('a[href="/web/submissions/1/updates/new"]');

    assert.strictEqual(currentURL(), '/submissions/1/updates/new');
    assert.dom('h1').hasText('Update Submission');

    // --- Upload file and submit ---

    const createdUpdate: SubmissionUpdate = {
      id: 42,
      status: 'waiting_validation',
      diff: null,
      error_message: null,
      created_at: now,
      processing: false,

      ddbj_record: {
        filename: 'updated.json',
        url: 'http://example.com/updated.json',
      },

      validation: null,
      submission,
    };

    worker.use(
      http.post('/submissions/{id}/updates', ({ response }) => {
        return response(202).json(createdUpdate);
      }),

      http.get('/submission_updates/{id}', ({ response }) => {
        return response(200).json({
          ...createdUpdate,
          status: 'ready_to_apply',
          diff: '--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new',

          validation: {
            id: 1,
            progress: 'finished',
            created_at: now,
            finished_at: now,
            validity: 'valid',
            details: [],
          },
        });
      }),
    );

    const file = new File(['{}'], 'updated.json', { type: 'application/json' });
    await triggerEvent('input[type="file"]', 'change', { files: [file] });

    await click('button[type="submit"]');
    await waitUntil(() => currentURL() === '/updates/42');

    // --- Update detail page (ready to apply) ---

    assert.dom('h1').hasText('Update-42');
    assert.dom('.badge').hasText('ready to apply');

    // --- Apply ---

    worker.use(
      http.patch('/submission_updates/{id}/submission', ({ response }) => {
        return response(204).empty();
      }),

      http.get('/submission_updates/{id}', ({ response }) => {
        return response(200).json({
          ...createdUpdate,
          status: 'applied',
          diff: '--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new',

          validation: {
            id: 1,
            progress: 'finished',
            created_at: now,
            finished_at: now,
            validity: 'valid',
            details: [],
          },
        });
      }),
    );

    await click('button.btn-primary');

    assert.dom('.badge').hasText('applied');
  });
});
