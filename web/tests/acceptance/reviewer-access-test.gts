import { module, test } from 'qunit';
import { visit, click, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type SubmissionRequest = components['schemas']['SubmissionRequest'];

const now = '2025-01-01T00:00:00.000Z';

const request: SubmissionRequest = {
  id: 42,
  db: 'bioproject',
  status: 'applied',
  error_message: null,
  created_at: now,
  processing: false,
  ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
  validation: null,
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
  submission: {
    id: 10,
    source_id: 'PSUB000042',
    created_at: now,
    updated_at: now,
    ddbj_record: { filename: 'test.json', url: 'http://example.com/test.json' },
    flatfile_na: null,
    flatfile_aa: null,
    accessions_count: 2,
  },
};

module('Acceptance | reviewer view (share link, no login)', function (hooks) {
  setupApplicationTest(hooks);
  // Deliberately no setupAuthentication — reviewers are not logged in.

  test('renders the request read-only, without messages', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json(request);
      }),
    );

    await visit('/reviews/secret-token');

    assert.strictEqual(currentURL(), '/reviews/secret-token');
    assert.dom('h1').hasText('#42');
    assert.dom('[role="note"]').includesText('reviewer');
    assert.dom('.badge').hasText('applied');

    // No messaging surface for reviewers.
    assert.dom('textarea').doesNotExist();
    assert.dom('h2').doesNotIncludeText('Messages');

    // ...but the accessions are reachable via the token-scoped route.
    assert.dom('a[href="/web/reviews/secret-token/accessions"]').exists();
  });

  test('a reviewer can open the accessions via the share token', async function (assert) {
    worker.use(
      http.get('/reviews/{token}', ({ response }) => {
        return response(200).json(request);
      }),

      http.get('/reviews/{token}/accessions', ({ response }) => {
        return response(200).json([{ number: 'ACC_R1', entry_id: 'E1', version: 1, locus_date: '2025-01-01' }]);
      }),
    );

    await visit('/reviews/secret-token/accessions');

    assert.strictEqual(currentURL(), '/reviews/secret-token/accessions');
    assert.dom('td').includesText('ACC_R1');
  });
});

module('Acceptance | reviewer access (submitter side)', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('enable shows the share URL and a disable button', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json([]);
      }),

      http.post('/submission_requests/{submission_request_id}/reviewer_access', ({ response }) => {
        return response(201).json({
          enabled: true,
          url: 'http://example.com/web/reviews/generated-token',
          expires_at: '2025-01-08T00:00:00.000Z',
        });
      }),
    );

    await visit('/requests/42');

    assert.dom('input[readonly]').doesNotExist(); // disabled initially

    // Several primary buttons share the page (message reply, etc.), so
    // target the reviewer-access one by its label.
    const enable = [...document.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Enable')!;
    await click(enable);

    assert.dom('input[readonly]').hasValue('http://example.com/web/reviews/generated-token');
    assert.dom('button.btn-outline-danger').hasText('Disable');
  });
});
