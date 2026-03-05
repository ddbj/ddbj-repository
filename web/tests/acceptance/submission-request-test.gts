import { module, test } from 'qunit';
import { visit, click, triggerEvent, currentURL, waitUntil } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];

const now = '2025-01-01T00:00:00.000Z';

module('Acceptance | submission request', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('create and apply', async function (assert) {
    // --- List page ---

    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], {
          headers: { 'Total-Pages': '1' },
        });
      }),
    );

    await visit('/requests');

    assert.strictEqual(currentURL(), '/requests');
    assert.dom('h1').hasText('Requests');

    // --- Navigate to new request page ---

    await click('a[href="/web/requests/new"]');

    assert.strictEqual(currentURL(), '/requests/new');
    assert.dom('h1').hasText('New Request');

    // --- Upload file and submit ---

    const createdRequest: SubmissionRequest = {
      id: 42,
      status: 'waiting_validation',
      error_message: null,
      created_at: now,
      processing: false,

      ddbj_record: {
        filename: 'test.json',
        url: 'http://example.com/test.json',
      },

      validation: null,
      submission: null,
    };

    worker.use(
      http.post('/submission_requests', ({ response }) => {
        return response(202).json(createdRequest);
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json({
          ...createdRequest,
          status: 'ready_to_apply',

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

    const file = new File(['{}'], 'test.json', { type: 'application/json' });
    await triggerEvent('input[type="file"]', 'change', { files: [file] });

    await click('button[type="submit"]');
    await waitUntil(() => currentURL() === '/requests/42');

    // --- Request detail page (ready to apply) ---
    assert.dom('h1').hasText('Request-42');
    assert.dom('.badge').hasText('ready to apply');

    // --- Apply ---

    worker.use(
      http.post('/submission_requests/{id}/submission', ({ response }) => {
        return response(204).empty();
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json({
          ...createdRequest,
          status: 'applied',

          validation: {
            id: 1,
            progress: 'finished',
            created_at: now,
            finished_at: now,
            validity: 'valid',
            details: [],
          },

          submission: {
            id: 10,
            created_at: now,
            updated_at: now,
            ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
            flatfile_na: { filename: 'test-na.flat', url: 'http://example.com/test-na.flat' },
            flatfile_aa: null,
            updates: [],
          },
        });
      }),
    );

    await click('button.btn-primary');
    await waitUntil(() => document.querySelector('.badge')?.textContent?.trim() === 'applied');

    assert.dom('.badge').hasText('applied');
  });
});
