import { module, test } from 'qunit';
import { visit, click, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Invitation = components['schemas']['Invitation'];

const invitation: Invitation = {
  set_name: 'Deep sea study',
  invited_by: 'colleague',
  email: 'newcomer@example.org',
  expires_at: '2025-02-01T00:00:00.000Z',
  status: 'open',
};

const joined = {
  id: 7,
  name: 'Deep sea study',
  owner_uid: 'colleague',
  owned: false,
  created_at: '2025-01-01T00:00:00.000Z',
  member_count: 2,
  invited_count: 0,
  submission_count: 0,
};

// WebsController injects this into the shell per environment; a test
// build has no shell, so the one place that reads it has to be given one.
function withAccountURL(hooks: NestedHooks, url = 'https://accounts.example.com/') {
  let tag: HTMLMetaElement;

  hooks.beforeEach(function () {
    tag = document.createElement('meta');
    tag.setAttribute('name', 'account-url');
    tag.setAttribute('content', url);
    document.head.append(tag);
  });

  hooks.afterEach(function () {
    tag.remove();
  });
}

module('Acceptance | invitation (no login yet)', function (hooks) {
  setupApplicationTest(hooks);
  withAccountURL(hooks);
  // Deliberately no setupAuthentication: the whole point is that the page
  // reads before the reader has an account, let alone a session.

  test('says what the invitation is for, and offers both ways in', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json(invitation);
      }),
    );

    await visit('/invitations/abc123');

    assert.dom().includesText('colleague');
    assert.dom().includesText('Deep sea study');
    assert.dom('[data-test-login]').hasText('Log in with DDBJ Account');
  });

  test('an expired invitation says so instead of hiding', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json({ ...invitation, status: 'expired' });
      }),
    );

    await visit('/invitations/abc123');

    assert.dom('.alert').includesText('This invitation has expired');
    assert.dom('[data-test-login]').doesNotExist();
    assert.dom('[data-test-join]').doesNotExist();
  });

  // The token is kept after acceptance precisely so this page can say so
  // — opening the mail again from another device used to be a 404.
  test('a link somebody has already used says so instead of erroring', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json({ ...invitation, status: 'accepted', expires_at: null });
      }),
    );

    await visit('/invitations/abc123');

    assert.dom('.alert').includesText('already been used');
    assert.dom('[data-test-join]').doesNotExist();
  });

  // An invitation token is a bearer credential. Handing it to DDBJ Account
  // would put it in that application's logs and in the Referer of every
  // link on its pages, so it waits here instead.
  test('going off to create an account does not take the token along', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json(invitation);
      }),
    );

    await visit('/invitations/abc123');

    const href = document.querySelector('[data-test-sign-up]')?.getAttribute('href');

    assert.ok(href, 'offers a way to create an account');
    assert.notOk(href?.includes('abc123'), 'the token is not in the URL handed to DDBJ Account');
    assert.ok(href?.includes('return_to='), 'but a way back is');
  });
});

// Coming back from DDBJ Account. The token is not in the URL DDBJ Account
// was given (it is a bearer credential), so this route picks it back up.
module('Acceptance | invitation resume', function (hooks) {
  setupApplicationTest(hooks);

  hooks.afterEach(function () {
    localStorage.removeItem('invitationToken');
  });

  test('picks the token back up and says the account is ready', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json(invitation);
      }),
    );

    localStorage.setItem('invitationToken', JSON.stringify({ token: 'abc123', at: Date.now() }));

    await visit('/invitation?signed_up=1');

    assert.strictEqual(currentURL(), '/invitations/abc123?signed_up=1');
    assert.dom('.alert-success').includesText('Your DDBJ Account is ready');

    // Spent: a second return has nothing to resume.
    assert.strictEqual(localStorage.getItem('invitationToken'), null);
  });

  // Creating an account is a round trip somebody can abandon. A token
  // left in storage must not resume an invitation weeks later.
  test('a token left over from an abandoned signup is not resumed', async function (assert) {
    localStorage.setItem('invitationToken', JSON.stringify({ token: 'abc123', at: Date.now() - 60 * 60 * 1000 }));

    await visit('/invitation');

    assert.strictEqual(currentURL(), '/login');
    assert.strictEqual(localStorage.getItem('invitationToken'), null);
  });

  test('with nothing waiting it goes to the front page rather than erroring', async function (assert) {
    await visit('/invitation');

    // The front page, which for somebody with no session is the sign-in
    // screen. Either way it is a place, not an error.
    assert.strictEqual(currentURL(), '/login');
  });
});

module('Acceptance | invitation (already signed in)', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('joining opens the set', async function (assert) {
    worker.use(
      http.get('/invitations/{token}', ({ response }) => {
        return response(200).json(invitation);
      }),

      http.post('/invitations/{invitation_token}/acceptance', ({ response }) => {
        return response(201).json(joined);
      }),

      http.get('/sets/{id}', ({ response }) => {
        return response(200).json({
          ...joined,
          members: [],
          submissions: [],
          deletable: true,
          delete_blocked_reason: null,
        });
      }),
    );

    await visit('/invitations/abc123');
    await click('[data-test-join]');

    assert.strictEqual(currentURL(), '/sets/7');
  });
});
