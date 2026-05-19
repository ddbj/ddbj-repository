import { module, test } from 'qunit';
import { visit, fillIn, click, currentURL } from '@ember/test-helpers';
import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../../msw/http';
import { worker } from '../../msw/worker';

const adminURL = `${ENV.apiURL}/admin/submissions`;

module('Acceptance | admin | submissions', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  hooks.beforeEach(() => {
    worker.use(
      http.get('/me', ({ response }) => {
        return response(200).json({
          uid: 'test-admin',
          api_key: 'test-api-key',
          admin: true,
        });
      }),
    );
  });

  test('lists submissions with db and user columns', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json(
          [
            {
              id: 1,
              db: 'st26',
              created_at: '2026-05-01T00:00:00Z',
              updated_at: '2026-05-01T00:00:00Z',
              user: { uid: 'alice' },
            },
            {
              id: 2,
              db: 'bioproject',
              created_at: '2026-05-02T00:00:00Z',
              updated_at: '2026-05-02T00:00:00Z',
              user: { uid: 'bob' },
            },
          ],
          { headers: { 'Total-Pages': '1' } },
        );
      }),
    );

    await visit('/admin/submissions');

    assert.dom('tbody tr').exists({ count: 2 });
    assert.dom('tbody tr:first-child').includesText('Submission-1');
    assert.dom('tbody tr:first-child').includesText('ST.26');
    assert.dom('tbody tr:first-child').includesText('alice');
  });

  test('filter form updates the URL with db and user query params', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, ({ request }) => {
        const url = new URL(request.url);
        const db = url.searchParams.get('db');
        const user = url.searchParams.get('user');

        if (db === 'bioproject' && user === 'bob') {
          return HttpResponse.json(
            [
              {
                id: 9,
                db: 'bioproject',
                created_at: '2026-05-03T00:00:00Z',
                updated_at: '2026-05-03T00:00:00Z',
                user: { uid: 'bob' },
              },
            ],
            { headers: { 'Total-Pages': '1' } },
          );
        }

        return HttpResponse.json([], { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/admin/submissions');

    await fillIn('select[name="db"]', 'bioproject');
    await fillIn('input[name="user"]', 'bob');
    await click('button[type="submit"]');

    assert.strictEqual(currentURL(), '/admin/submissions?db=bioproject&user=bob');
    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr').includesText('Submission-9');
  });

  test('empty result shows the placeholder row', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json([], { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/admin/submissions');

    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr').includesText('No submissions found.');
  });
});
