import { module, test } from 'qunit';
import { visit, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

module('Acceptance | sign-in', function (hooks) {
  setupApplicationTest(hooks);

  // The entry point used to be the `{{else}}` of a logged-in check inside
  // the requests list, so the one page a first-time visitor sees was a
  // button with no statement of what the system is.
  test('an unauthenticated visit lands on a page that says what this is', async function (assert) {
    await visit('/');

    assert.strictEqual(currentURL(), '/login');
    assert.dom('h1').hasText('Submit and track your data with DDBJ');
    assert.dom('form[action$="/auth/keycloak"] button').exists();
  });

  // Two groups who land here need no account at all; without a visible
  // branch they become help desk traffic.
  test('it routes away the people who do not need an account', async function (assert) {
    await visit('/login');

    assert.dom('main').includesText('reviewer share link');
    assert.dom('main').includesText('API key');
  });

  test('the requests list is not rendered without a session', async function (assert) {
    await visit('/');

    assert.dom('table').doesNotExist();
    assert.dom('h1').doesNotIncludeText('My submissions');
  });
});

module('Acceptance | sign-in (authenticated)', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  hooks.beforeEach(function () {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(200).json([], { headers: { 'Total-Pages': '1' } });
      }),
    );
  });

  test('a session goes straight to the list', async function (assert) {
    await visit('/');

    assert.strictEqual(currentURL(), '/');
    assert.dom('h1').hasText('My submissions');
  });

  // 401 means the session ended somewhere else. A modal would cover the
  // screen the person was working on in order to say so.
  test('a 401 raises a banner rather than the error modal', async function (assert) {
    worker.use(
      http.get('/submission_requests', ({ response }) => {
        return response(401).json({ error: 'Unauthorized' });
      }),
    );

    await visit('/');

    assert.dom('[role="alert"]').includesText('You are signed out');
    assert.dom('.modal.show').doesNotExist();
    assert.dom('[role="alert"] form[action$="/auth/keycloak"]').exists('offers a way back in');
  });
});
