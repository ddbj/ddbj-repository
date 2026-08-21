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
    // `fillIn` addresses by selector, so the name a person would use is
    // asserted rather than used: without it the control is unlabelled
    // for a screen reader and nothing here would notice.
    assert.dom('[data-test-set-messages] label').hasText('Write to the set');
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

  // Ember reuses the component when the model changes under the same
  // route. Without a re-fetch, one set's conversation stays on screen
  // under another set's name — which, in a feature about who is party to
  // which conversation, is the worst thing it could get wrong.
  test("moving to another set fetches that set's thread", async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ params, response }) =>
        response(200).json(set({ id: Number(params.id), name: `Set ${params.id}` })),
      ),

      http.get('/sets/{set_id}/messages', ({ params, response }) =>
        response(200).json([message({ body: `thread for set ${params.set_id}` })]),
      ),
    );

    await visit('/sets/7');

    assert.dom('[data-test-set-messages]').includesText('thread for set 7');

    await visit('/sets/8');

    assert.dom('[data-test-set-messages]').includesText('thread for set 8');
    assert.dom('[data-test-set-messages]').doesNotIncludeText('thread for set 7');
  });

  // Until the thread has arrived there is nothing to acknowledge: with
  // no id the server falls back to "now" and would discharge messages
  // the reader never saw.
  test('the acknowledge button waits until it knows what is on screen', async function (assert) {
    let sent: unknown;

    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set({ unread_message_count: 1 }))),

      http.get('/sets/{set_id}/messages', ({ response }) =>
        response(200).json([message({ id: 42, author_role: 'curator', author_uid: 'bob' })]),
      ),

      http.post('/sets/{set_id}/messages/read', async ({ request, response }) => {
        sent = (await request.json())?.through_id;

        return response(204).empty();
      }),
    );

    await visit('/sets/7');
    await click('[data-test-set-messages] [data-test-mark-read]');

    assert.strictEqual(sent, 42, 'it names the newest message it had in front of it');
  });

  // A long conversation arrives from its newest end. What is missing is
  // the beginning, and asking for it must not depend on a page number
  // that moves every time somebody writes.
  test('the beginning of a long thread is asked for by cursor', async function (assert) {
    let asked: string | null = null;

    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set())),

      http.get('/sets/{set_id}/messages', ({ request, response }) => {
        asked = new URL(request.url).searchParams.get('before_id');

        return asked
          ? response(200).json([message({ id: 1, body: 'the first thing anybody said' })])
          : response(200).json([message({ id: 9, body: 'the latest thing' })], {
              headers: { 'Total-Count': '2' },
            });
      }),
    );

    await visit('/sets/7');

    assert.dom('[data-test-set-messages]').includesText('the latest thing');
    assert.dom('[data-test-show-earlier]').exists('the thread says it has a beginning');

    await click('[data-test-show-earlier]');

    assert.strictEqual(asked, '9', 'asked for what is older than the oldest on screen');
    assert.dom('[data-test-set-messages]').includesText('the first thing anybody said');
    assert.dom('[data-test-show-earlier]').doesNotExist('and there is no more of it');
  });

  // Posting counts. With 51 messages and 50 on screen, one reply would
  // otherwise make the lengths match and take "Show earlier messages"
  // away with the first message still unread.
  test('replying does not take the beginning of the thread away', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set())),

      http.get('/sets/{set_id}/messages', ({ response }) =>
        response(200).json([message({ id: 9 })], { headers: { 'Total-Count': '2' } }),
      ),

      http.post('/sets/{set_id}/messages', ({ response }) => response(201).json(message({ id: 10 }))),
    );

    await visit('/sets/7');

    assert.dom('[data-test-show-earlier]').exists();

    await fillIn('[data-test-set-messages] textarea', 'One more thing.');
    await click('[data-test-set-messages] button[type="submit"]');

    assert.dom('[data-test-show-earlier]').exists('the beginning is still there to fetch');
  });

  // A thread that arrived whole must not offer to fetch what is not
  // there.
  test('a short thread offers nothing to load', async function (assert) {
    worker.use(
      http.get('/sets/{id}', ({ response }) => response(200).json(set())),

      http.get('/sets/{set_id}/messages', ({ response }) =>
        response(200).json([message()], { headers: { 'Total-Count': '1' } }),
      ),
    );

    await visit('/sets/7');

    assert.dom('[data-test-show-earlier]').doesNotExist();
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
