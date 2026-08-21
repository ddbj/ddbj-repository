import { module, test } from 'qunit';
import { visit, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';

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

  // The token is the only copy of the session — getting another means the
  // whole OAuth round trip — so it is discarded only when the server says
  // it is no good. A dev server that is down, a proxy in the way, a
  // laptop off the network: none of those are an answer about the token,
  // and each of them used to sign the person out for the rest of the day.
  test('a server that cannot answer does not sign anybody out', async function (assert) {
    worker.use(
      mswHttp.get(`${ENV.apiURL}/me`, () => HttpResponse.json({ error: 'Internal server error' }, { status: 500 })),
    );

    await visit('/');

    assert.strictEqual(localStorage.getItem('token'), 'test-token', 'the token is still there');
    assert.dom('[data-test-unreachable]').includesText('Could not reach the server');
    assert.dom('[role="alert"]').doesNotIncludeText('You are signed out');
  });

  // 401 is an answer about the token, and the only one that discards it.
  test('a 401 from /me does discard the token', async function (assert) {
    worker.use(http.get('/me', ({ response }) => response(401).json({ error: 'Unauthorized' })));

    await visit('/');

    assert.strictEqual(localStorage.getItem('token'), null);
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
