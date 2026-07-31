import { module, test } from 'qunit';
import { visit, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

module('Acceptance | attention banner', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  hooks.beforeEach(function () {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], { headers: { 'Total-Pages': '1' } });
      }),
    );
  });

  test('stays out of the way when nothing is waiting', async function (assert) {
    await visit('/');

    assert.dom('[role="status"].alert').doesNotExist();
  });

  // The point of the banner is that it is visible from anywhere — a row
  // badge on page 1 of a long list is not.
  test('names the waiting requests and links to them', async function (assert) {
    worker.use(
      http.get('/attention', ({ response }) => {
        return response(200).json({
          requests: [
            { id: 42, db: 'biosample', source_id: 'SSUB000123' },
            { id: 7, db: 'bioproject', source_id: null },
          ],
        });
      }),
    );

    await visit('/');

    assert.dom('[role="status"].alert').includesText('2 submissions need your reply.');
    assert.dom('[role="status"].alert').includesText('SSUB000123');
    assert.dom('[role="status"].alert a[href="/web/requests/42"]').exists();
  });

  test('uses the singular for one request', async function (assert) {
    worker.use(
      http.get('/attention', ({ response }) => {
        return response(200).json({ requests: [{ id: 42, db: 'st26', source_id: null }] });
      }),
    );

    await visit('/');

    assert.dom('[role="status"].alert').includesText('1 submission needs your reply.');
  });

  // Replying should clear the notice without a reload, so the banner is
  // refreshed on navigation rather than only at boot.
  test('clears itself after a navigation once the request is answered', async function (assert) {
    let answered = false;

    worker.use(
      http.get('/attention', ({ response }) => {
        return response(200).json({
          requests: answered ? [] : [{ id: 42, db: 'st26', source_id: null }],
        });
      }),
    );

    await visit('/');
    assert.dom('[role="status"].alert').exists();

    answered = true;
    await click('a[href="/web/new"]');

    assert.dom('[role="status"].alert').doesNotExist();
  });

  test('a failure to load it never takes the page down', async function (assert) {
    worker.use(
      http.get('/attention', ({ response }) => {
        return response(401).json({ error: 'Unauthorized' });
      }),
    );

    await visit('/');

    assert.dom('[role="status"].alert').doesNotExist();
    assert.dom('h1').hasText('My submissions');
  });
});
