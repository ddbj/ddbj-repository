import { module, test } from 'qunit';
import { visit, fillIn, click, currentURL } from '@ember/test-helpers';
import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../../msw/http';
import { worker } from '../../msw/worker';

const adminURL = `${ENV.apiURL}/admin/submission_requests`;

module('Acceptance | admin | requests', function (hooks) {
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

  test('lists requests with db and user columns', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json(
          [
            { id: 1, db: 'st26', status: 'applied', created_at: '2026-05-01T00:00:00Z', user: { uid: 'alice' } },
            { id: 2, db: 'biosample', status: 'validating', created_at: '2026-05-02T00:00:00Z', user: { uid: 'bob' } },
          ],
          { headers: { 'Total-Pages': '1' } },
        );
      }),
    );

    await visit('/admin/requests');

    assert.dom('tbody tr').exists({ count: 2 });
    assert.dom('tbody tr:first-child').includesText('Request-1');
    assert.dom('tbody tr:first-child').includesText('ST.26');
    assert.dom('tbody tr:first-child').includesText('alice');
  });

  test('filter form updates the URL with db and user query params', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, ({ request }) => {
        const url = new URL(request.url);
        const db = url.searchParams.get('db');
        const user = url.searchParams.get('user');

        if (db === 'biosample' && user === 'alice') {
          return HttpResponse.json(
            [
              {
                id: 9,
                db: 'biosample',
                status: 'applied',
                created_at: '2026-05-03T00:00:00Z',
                user: { uid: 'alice' },
              },
            ],
            { headers: { 'Total-Pages': '1' } },
          );
        }

        return HttpResponse.json([], { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/admin/requests');

    await fillIn('select[name="db"]', 'biosample');
    await fillIn('input[name="user"]', 'alice');
    await click('button[type="submit"]');

    assert.strictEqual(currentURL(), '/admin/requests?db=biosample&user=alice');
    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr').includesText('Request-9');
  });

  test('empty result shows the placeholder row', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json([], { headers: { 'Total-Pages': '1' } });
      }),
    );

    await visit('/admin/requests');

    assert.dom('tbody tr').exists({ count: 1 });
    assert.dom('tbody tr').includesText('No requests found.');
  });
});
