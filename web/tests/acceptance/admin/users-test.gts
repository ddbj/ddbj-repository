import { module, test } from 'qunit';
import { visit, click, fillIn } from '@ember/test-helpers';
import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { worker } from '../../msw/worker';

const userURL = `${ENV.apiURL}/admin/users/alice`;

const profile = {
  uid: 'alice',
  full_name: 'Alice Liddell',
  email: 'alice@example.com',
  organization: 'Wonderland',
  account_type_number: 'general',
  admin: false,
  notes: '',
  submission_requests_count: 5,
  submissions_count: 3,
};

module('Acceptance | admin | user detail', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks, { admin: true });

  hooks.beforeEach(() => {
    worker.use(mswHttp.get(userURL, () => HttpResponse.json(profile)));
  });

  test('renders the cloakman profile and activity links with counts', async (assert) => {
    await visit('/admin/users/alice');

    assert.dom('h1').hasText('alice');
    assert.dom('dl').includesText('Alice Liddell');
    assert.dom('dl').includesText('alice@example.com');
    assert.dom('dl').includesText('Wonderland');
    assert.dom('a[href*="/admin/requests"]').includesText('Submission requests (5)');
    assert.dom('a[href*="/admin/submissions"]').includesText('Submissions (3)');
  });

  test('saves notes via PATCH and writes the response back into the model', async (assert) => {
    worker.use(
      mswHttp.patch(userURL, async ({ request }) => {
        const body = (await request.json()) as { user: { notes: string } };

        return HttpResponse.json({ notes: body.user.notes });
      }),
    );

    await visit('/admin/users/alice');

    assert.dom('textarea[name="notes"]').hasValue('');

    await fillIn('textarea[name="notes"]', 'Watch this account.');
    await click('main form button[type="submit"]');

    assert.dom('textarea[name="notes"]').hasValue('Watch this account.');
  });

  test('proxy login toggle activates and deactivates', async (assert) => {
    await visit('/admin/users/alice');

    assert.dom('button.btn-outline-primary').includesText('Proxy login as alice');

    await click('button.btn-outline-primary');

    assert.dom('.alert-warning').includesText('Currently acting as');
    assert.dom('.alert-warning strong').hasText('alice');

    await click('.alert-warning button');

    assert.dom('.alert-warning').doesNotExist();
    assert.dom('button.btn-outline-primary').includesText('Proxy login as alice');
  });
});
