import { module, test } from 'qunit';
import { visit, click, fillIn, currentURL } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Set = components['schemas']['Set'];
type SetSummary = components['schemas']['SetSummary'];

const now = '2025-01-01T00:00:00.000Z';

const summary: SetSummary = {
  id: 7,
  name: 'Deep sea study',
  owner_uid: 'test-user',
  owned: true,
  created_at: now,
  member_count: 2,
  invited_count: 1,
  submission_count: 1,
  unread_message_count: 0,
};

const set: Set = {
  ...summary,
  deletable: false,
  delete_blocked_reason:
    'Take the submissions out and remove everyone else — including invitations nobody has used — first.',

  members: [
    {
      id: 1,
      email: null,
      uid: 'test-user',
      status: 'accepted',
      owner: true,
      you: true,
      invited_by: 'test-user',
      joined_at: now,
      invitation_expires_at: null,
      removable: false,
      submission_count: 0,
      invited_address_match: null,
      invitation_url: null,
      mail_deliverable: null,
    },
    {
      id: 2,
      email: 'colleague@example.org',
      uid: 'colleague',
      status: 'accepted',
      owner: false,
      you: false,
      invited_by: 'test-user',
      joined_at: now,
      invitation_expires_at: null,
      removable: true,
      submission_count: 1,
      invited_address_match: 'different',
      invitation_url: null,
      mail_deliverable: null,
    },
    {
      id: 3,
      email: 'newcomer@example.org',
      uid: null,
      status: 'open',
      owner: false,
      you: false,
      invited_by: 'test-user',
      joined_at: null,
      invitation_expires_at: '2025-02-01T00:00:00.000Z',
      removable: true,
      submission_count: 0,
      invited_address_match: null,
      invitation_url: 'http://localhost:4200/web/invitations/tok123',
      mail_deliverable: false,
    },
  ],

  submissions: [
    {
      added_at: now,
      owner_uid: 'colleague',
      owned: false,

      submission: {
        id: 42,
        db: 'bioproject',
        status: 'applied',
        created_at: now,
        closed_at: null,
        submission_id: 10,
        source_id: 'PSUB000042',
        first_accession: 'PRJDB1234',
        accession_count: 1,
        processing: false,
        unread_curator_message_count: 0,

        progress: {
          step: 'curating',
          failed: false,
          closed: false,
          row_count: 1,
          accessioned_count: 1,
          hold_date: null,
        },
      },
    },
  ],
};

module('Acceptance | sets', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('the list says what a set is for when there are none yet', async function (assert) {
    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([]);
      }),
    );

    await visit('/sets');

    assert.dom('[data-test-sets]').doesNotExist();
    assert.dom().includesText('You are not in any set yet');
  });

  test('creating one opens it', async function (assert) {
    worker.use(
      http.get('/sets', ({ response }) => {
        return response(200).json([]);
      }),

      http.post('/sets', ({ response }) => {
        return response(201).json({ ...set, members: [set.members[0]!], submissions: [] });
      }),

      http.get('/sets/{id}', ({ response }) => {
        return response(200).json({
          ...set,
          members: [set.members[0]!],
          submissions: [],
          submission_count: 0,
          deletable: true,
          delete_blocked_reason: null,
        });
      }),
    );

    await visit('/sets');
    await fillIn('input[type="text"]', 'Deep sea study');
    await click('button[type="submit"]');

    assert.strictEqual(currentURL(), '/sets/7');
    assert.dom().includesText('Deep sea study');
  });

  test('the roster shows who has joined, who has not, and who came in at another address', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-members]').includesText('colleague');
    assert.dom('[data-test-members]').includesText('newcomer@example.org');
    assert.dom('[data-test-members]').includesText('Invited');
    assert.dom('[data-test-members]').includesText('registered at a different address');
  });

  // Every deployed environment restricts outgoing mail while sending to
  // real submitters is switched off. Without this the inviter has no way
  // to know their invitation reached nobody.
  test('an invitation whose mail goes nowhere says so, and offers the link', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-members]').includesText('not being sent from this environment');
    assert.dom('[aria-label="Copy the invitation link for newcomer@example.org"]').exists();
  });

  test('removing somebody says what goes with them, and asks first', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');
    await click('[aria-label="Remove colleague"]');

    assert.dom('[data-test-members]').includesText('Their 1 submission will be taken out of the set');

    // Nothing has been sent yet — it asked.
    await click('[data-test-members] button.btn-link');

    assert.dom('[data-test-members]').doesNotIncludeText('will be taken out of the set');
  });

  test('a row you may not remove offers no way to', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');

    // The owner's own row: nobody may remove them, and they cannot walk
    // out of a set that would then have nobody to delete it.
    assert.dom('[aria-label="Leave this set"]').doesNotExist();
  });

  test('the owner is told why a set cannot be deleted, rather than shown nothing', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-delete]').isDisabled();
    assert.dom().includesText('Take the submissions out and remove everyone else');
  });

  test('an empty set of your own can just be deleted', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json({
          ...set,
          members: [set.members[0]!],
          submissions: [],
          submission_count: 0,
          deletable: true,
          delete_blocked_reason: null,
        });
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-delete]').isNotDisabled();
    assert.dom().doesNotIncludeText('Take the submissions out and remove everyone else');
  });

  test('the owner can rename it', async function (assert) {
    let name = set.name;

    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json({ ...set, name });
      }),

      http.patch('/sets/{id}', ({ response }) => {
        name = 'Renamed study';

        return response(200).json({ ...set, name });
      }),
    );

    await visit('/sets/7');
    await click('[data-test-rename]');
    await fillIn('input[type="text"]', 'Renamed study');
    await click('button[type="submit"]');

    assert.dom('h1').includesText('Renamed study');
  });

  test('a refused invitation lands on the field, not in a modal over the page', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),

      http.post('/sets/{set_id}/members', ({ response }) => {
        return response(422).json({ error: 'Email is already a member of this set' });
      }),
    );

    await visit('/sets/7');
    await fillIn('input[type="email"]', 'colleague@example.org');
    await click('button[type="submit"]');

    assert.dom('[data-test-invite-error]').includesText('already a member');
    assert.dom('.modal.show').doesNotExist();
  });

  test('a submission somebody else put in is listed but not removable', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json(set);
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-submissions]').includesText('PSUB000042');
    assert.dom('[data-test-submissions]').includesText('colleague');
    assert.dom('[data-test-submissions] button').doesNotExist();
  });

  // The server says whose it is — the client cannot work it out, because
  // under a proxy login the account it believes it is is not the account
  // the server acts as.
  test('your own submission in a set can be taken back out', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => {
        return response(200).json({
          ...set,
          submissions: [{ ...set.submissions[0]!, owner_uid: 'test-user', owned: true }],
        });
      }),
    );

    await visit('/sets/7');

    assert.dom('[aria-label="Take PSUB000042 out of this set"]').exists();
  });
});
