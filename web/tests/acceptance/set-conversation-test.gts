import { module, test } from 'qunit';
import { visit, click, fillIn } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Set = components['schemas']['Set'];
type SetMessage = components['schemas']['SetMessage'];

const now = '2025-01-01T00:00:00.000Z';

function set(overrides: Partial<Set> = {}): Set {
  return {
    id: 7,
    name: 'Deep sea study',
    owner_uid: 'test-user',
    owned: true,
    created_at: now,
    member_count: 2,
    invited_count: 0,
    submission_count: 0,
    unread_message_count: 0,
    deletable: true,
    delete_blocked_reason: null,
    members: [],
    submissions: [],
    ...overrides,
  };
}

function message(overrides: Partial<SetMessage> = {}): SetMessage {
  return {
    id: 1,
    body: 'Are these two projects one submission or two?',
    author_role: 'member',
    author_uid: 'test-user',
    created_at: now,
    files: [],
    ...overrides,
  };
}

// The set's own thread: one conversation about the bundle, which every
// member reads and writes. The submissions' own threads are not part of
// it — those stay between their owner and DDBJ.
module('Acceptance | the conversation about a set', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('the thread names which member wrote what, and marks your own', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set())),

      http.get('/sets/{set_id}/messages', ({ response }) =>
        response(200).json([
          message({ id: 1, author_uid: 'test-user', body: 'Are these one submission or two?' }),
          message({ id: 2, author_role: 'curator', author_uid: 'bob', body: 'Two — one per organism.' }),
          message({ id: 3, author_uid: 'colleague', body: 'Thanks, I will split mine.' }),
        ]),
      ),
    );

    await visit('/sets/7');

    const authors = [...document.querySelectorAll('[data-test-set-messages] li strong')].map((el) =>
      el.textContent?.trim(),
    );

    assert.deepEqual(authors, ['You', 'DDBJ curator', 'colleague'], 'a set has more than one voice on its side');
  });

  test('posting sends the body and appends what came back', async function (assert) {
    let posted: string | undefined;

    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set())),

      http.get('/sets/{set_id}/messages', ({ response }) => response(200).json([])),

      http.post('/sets/{set_id}/messages', async ({ request, response }) => {
        posted = (await request.json()).submission_set_message.body;

        return response(201).json(message({ id: 9, body: 'Both, actually.' }));
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-set-messages]').includesText('No messages yet');

    await fillIn('[data-test-set-messages] textarea', 'Both, actually.');
    await click('[data-test-set-messages] button[type="submit"]');

    assert.strictEqual(posted, 'Both, actually.');
    assert.dom('[data-test-set-messages]').includesText('Both, actually.');
    assert.dom('[data-test-set-messages] textarea').hasValue('');
  });

  // Reading is not answering, and the count is the server's: a message
  // here carries no read mark, because where each member has got to is a
  // fact about the person rather than about the message.
  test('a note that needs no reply is dealt with explicitly', async function (assert) {
    let read = false;

    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set({ unread_message_count: read ? 0 : 1 }))),

      http.get('/sets/{set_id}/messages', ({ response }) =>
        response(200).json([message({ author_role: 'curator', author_uid: 'bob', body: 'For your information.' })]),
      ),

      http.post('/sets/{set_id}/messages/read', ({ response }) => {
        read = true;

        return response(204).empty();
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-set-messages] [data-test-mark-read]').exists();

    await click('[data-test-set-messages] [data-test-mark-read]');

    assert.true(read);
    assert.dom('[data-test-set-messages] [data-test-mark-read]').doesNotExist();
  });

  // A badge on a row is only visible if that row is on the page in front
  // of you. The nav carries it from wherever the member happens to be.
  test('a set waiting on you is visible from any screen', async function (assert) {
    worker.use(
      http.get('/attention', ({ response }) => response(200).json({ requests: [], sets_waiting: 2 })),

      http.get('/submission_requests', ({ response }) =>
        response(200).json([], { headers: { 'Total-Pages': '1', 'Unfinished-Count': '0', 'Finished-Count': '0' } }),
      ),
    );

    await visit('/');

    assert.dom('[data-test-sets-waiting]').hasText('2');
  });
});
