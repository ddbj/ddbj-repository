import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL, waitUntil } from '@ember/test-helpers';
import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../../msw/http';
import { worker } from '../../msw/worker';

const adminURL = `${ENV.apiURL}/admin/regenerate_flatfiles`;

module('Acceptance | admin | regenerate flatfiles', function (hooks) {
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

  test('initial display shows form without completion message', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json({ loading: false, total: null, processed: null });
      }),
    );

    await visit('/admin/regenerate-flatfiles');

    assert.strictEqual(currentURL(), '/admin/regenerate-flatfiles');
    assert.dom('input[type="date"]').exists();
    assert.dom('button[type="submit"]').hasText('Regenerate');
    assert.dom('.alert-success').doesNotExist();
    assert.dom('.progress').doesNotExist();
  });

  test('completion message is not shown on initial load even if a previous run completed', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json({ loading: false, total: 5, processed: 5 });
      }),
    );

    await visit('/admin/regenerate-flatfiles');

    assert.dom('.alert-success').doesNotExist();
  });

  test('progress bar is shown while loading', async (assert) => {
    worker.use(
      mswHttp.get(adminURL, () => {
        return HttpResponse.json({ loading: true, total: 10, processed: 3 });
      }),
    );

    await visit('/admin/regenerate-flatfiles');

    assert.dom('.progress').exists();
    assert.dom('.card-body p').includesText('3 / 10');
    assert.dom('button[type="submit"]').hasAttribute('disabled');
    assert.dom('input[type="date"]').hasAttribute('disabled');
  });

  test('submit POSTs the date and shows completion', async (assert) => {
    let postCalled = false;

    worker.use(
      mswHttp.get(adminURL, () => {
        if (postCalled) {
          return HttpResponse.json({ loading: false, total: 3, processed: 3 });
        }

        return HttpResponse.json({ loading: false, total: null, processed: null });
      }),

      mswHttp.post(adminURL, async ({ request }) => {
        const body = (await request.json()) as { date: string };

        assert.strictEqual(body.date, '2026-07-01');

        postCalled = true;

        return new HttpResponse('{}', { status: 202, headers: { 'Content-Type': 'application/json' } });
      }),
    );

    await visit('/admin/regenerate-flatfiles');

    await fillIn('input[type="date"]', '2026-07-01');
    await click('button[type="submit"]');

    await waitUntil(() => document.querySelector('.alert-success') !== null);

    assert.dom('.alert-success').includesText('3 submissions regenerated');
  });
});
