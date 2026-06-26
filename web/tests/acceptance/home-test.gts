import { module, test } from 'qunit';
import { visit, click, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

const now = '2025-01-01T00:00:00.000Z';

module('Acceptance | home', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('lists submission requests across databases', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json(
          [
            {
              id: 7,
              db: 'biosample',
              status: 'applied',
              created_at: now,
              submission_id: 42,
              has_accession: true,
            },
            {
              id: 3,
              db: 'bioproject',
              status: 'validating',
              created_at: now,
              submission_id: null,
              has_accession: false,
            },
          ],
          {
            headers: { 'Total-Pages': '1' },
          },
        );
      }),
    );

    await visit('/');

    assert.strictEqual(currentURL(), '/');
    assert.dom('h1').hasText('Submission Requests');
    assert.dom('tbody tr').exists({ count: 2 });

    const firstRow = 'tbody tr:nth-child(1)';
    assert.dom(`${firstRow} td:nth-child(1)`).hasText('Request-7');
    assert.dom(`${firstRow} td:nth-child(2)`).hasText('BioSample');
    assert.dom(`${firstRow} td:nth-child(3) .badge`).hasText('Accessioned');
    assert.dom(`${firstRow} td:nth-child(4) a`).hasText('Submission-42');

    const secondRow = 'tbody tr:nth-child(2)';
    assert.dom(`${secondRow} td:nth-child(1)`).hasText('Request-3');
    assert.dom(`${secondRow} td:nth-child(2)`).hasText('BioProject');
    assert.dom(`${secondRow} td:nth-child(3) .badge`).hasText('validating');
    assert.dom(`${secondRow} td:nth-child(4) a`).doesNotExist();
  });

  test('empty state links to /new', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], {
          headers: { 'Total-Pages': '1' },
        });
      }),
    );

    await visit('/');

    assert.dom('table').doesNotExist();
    assert.dom('a[href="/web/new"]').exists({ count: 2 });
  });

  test('"New Submission" navigates to /new with database picker', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], {
          headers: { 'Total-Pages': '1' },
        });
      }),
    );

    await visit('/');
    await click('.btn-primary');

    assert.strictEqual(currentURL(), '/new');
    assert.dom('h1').hasText('New Submission');
    assert.dom('a[href="/web/st26/requests/new"]').exists();
    assert.dom('a[href="/web/bioproject/requests/new"]').exists();
    assert.dom('a[href="/web/biosample/requests/new"]').exists();
  });
});
