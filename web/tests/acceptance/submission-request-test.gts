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
    // --- Database picker ---

    await visit('/new');

    assert.strictEqual(currentURL(), '/new');
    assert.dom('h1').hasText('New Submission');

    // --- Navigate to new request page ---

    await click('a[href="/web/st26/requests/new"]');

    assert.strictEqual(currentURL(), '/st26/requests/new');
    assert.dom('h1').hasText('New Submission (ST.26)');

    // The four steps of making a submission, with this one marked.
    assert.dom('[data-test-submission-steps] [data-test-step="2"]').hasAttribute('aria-current', 'step');
    assert.dom('button[type="submit"]').hasText('Check my data');

    // --- Upload file and submit ---

    const createdRequest: SubmissionRequest = {
      id: 42,
      db: 'st26',
      status: 'waiting_validation',
      error_code: null,
      error_message: null,
      created_at: now,
      closed_at: null,
      closable: false,
      processing: false,

      ddbj_record: {
        filename: 'test.json',
        url: 'http://example.com/test.json',
      },

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

      // The request detail page renders the curator ↔ submitter thread.
      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),
    );

    const file = new File(['{}'], 'test.json', { type: 'application/json' });
    await triggerEvent('input[type="file"]', 'change', { files: [file] });

    await click('button[type="submit"]');
    await waitUntil(() => currentURL() === '/requests/42');

    // --- Request detail page (ready to apply) ---
    // The detail leads with what the submitter should do, not with the
    // raw status enum.
    assert.dom('h1').hasText('#42');
    assert.dom('[data-test-state] .badge').hasText('Action needed');
    assert.dom('[data-test-state] h2').hasText('Your file passed validation and is ready to submit');

    // --- Apply ---

    worker.use(
      http.post('/submission_requests/{id}/submission', ({ response }) => {
        return response(204).empty();
      }),

      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json({
          ...createdRequest,
          status: 'applied',

          progress: {
            step: 'curating',
            failed: false,
            closed: false,
            row_count: 1,
            accessioned_count: 0,
            hold_date: null,
          },

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
            source_id: null,
            created_at: now,
            updated_at: now,
            ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
            flatfile_na: { filename: 'test-na.flat', url: 'http://example.com/test-na.flat' },
            flatfile_aa: null,
            accessions_count: 0,
          },
        });
      }),
    );

    await click('[data-test-state] button.btn-primary');
    await waitUntil(() => document.querySelector('[data-test-state] .badge')?.textContent?.trim() === 'With DDBJ');

    assert.dom('[data-test-state] h2').hasText('A curator is reviewing your submission');
  });
});
