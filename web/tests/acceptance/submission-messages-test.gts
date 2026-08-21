import { module, test } from 'qunit';
import { visit, fillIn, click, triggerEvent, waitUntil, settled } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type Message = components['schemas']['Message'];

const now = '2025-01-01T00:00:00.000Z';

// Minimal request shape the show route needs to render. The thread now
// hangs off the request, so the submission may or may not be present.
const request: components['schemas']['SubmissionRequest'] = {
  id: 1,
  db: 'st26',
  status: 'applied',
  error_code: null,
  error_message: null,
  created_at: now,
  closed_at: null,
  closable: false,
  processing: false,
  ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
  validation: null,

  progress: {
    step: 'curating',
    failed: false,
    closed: false,
    row_count: 1,
    accessioned_count: 0,
    hold_date: null,
  },
  unread_curator_message_count: 0,
  last_message_at: '2025-01-02T09:30:00.000Z',
  sets: [],
  owned: true,
  owner_uid: 'test-user',
  submission: {
    id: 10,
    source_id: null,
    created_at: now,
    updated_at: now,
    ddbj_record: { filename: 'original.json', url: 'http://example.com/original.json' },
    flatfile_na: null,
    flatfile_aa: null,
    accessions_count: 0,
  },
};

module('Acceptance | submission messages', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  // "I have seen it" and "I have dealt with it" are different events.
  // Discharging the second by rendering the first took away the only
  // reminder a submitter had that they still owed an answer.
  test('a note that needs no reply is dealt with explicitly', async function (assert) {
    let read = false;

    const question: Message[] = [
      {
        id: 1,
        body: 'For your information — no reply needed.',
        author_role: 'curator',
        author_uid: 'alice',
        created_at: now,
        read_at: null,
        files: [],
      },
    ];

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) =>
        response(200).json(read ? question.map((m) => ({ ...m, read_at: now })) : question),
      ),

      http.post('/submission_requests/{submission_request_id}/messages/read', ({ response }) => {
        read = true;

        return response(204).empty();
      }),
    );

    await visit(`/requests/${request.id}`);

    assert.dom('[data-test-mark-read]').exists('reading it is not what deals with it');

    await click('[data-test-mark-read]');

    assert.true(read);
    assert.dom('[data-test-mark-read]').doesNotExist();
  });

  // "Here is the corrected file" is most of what this conversation is
  // for, and it was the one thing the thread could not carry.
  test('an attachment is listed on the message that brought it', async function (assert) {
    const withFile: Message[] = [
      {
        id: 1,
        body: 'Corrected sheet attached.',
        author_role: 'curator',
        author_uid: 'alice',
        created_at: now,
        read_at: null,
        files: [{ filename: 'samples.tsv', byte_size: 2048, url: 'http://example.com/samples.tsv' }],
      },
    ];

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json(withFile)),
    );

    await visit(`/requests/${request.id}`);

    assert.dom('[data-test-messages]').includesText('samples.tsv');
    assert.dom('[data-test-messages]').includesText('2.0 KB', 'the size answers "which file is this"');
    // A button, not an anchor: the address refuses a request carrying no
    // credentials, and a browser navigation carries none. See
    // DownloadsService.
    assert.dom('[data-test-messages] [data-test-download]').hasText('samples.tsv');
  });

  // "Here is the corrected file" needs no prose, and the textarea's
  // `required` made that path unreachable: the browser blocked the form
  // before any of the component's own logic ran.
  test('a submitter can send a file with no message', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      http.post('/submission_requests/{submission_request_id}/messages', ({ response }) =>
        response(201).json({
          id: 9,
          body: '',
          author_role: 'submitter',
          author_uid: 'alice',
          created_at: now,
          read_at: null,
          files: [{ filename: 'samples.tsv', byte_size: 12, url: 'http://example.com/samples.tsv' }],
        }),
      ),
    );

    await visit(`/requests/${request.id}`);

    assert.dom('textarea').doesNotHaveAttribute('required', 'an attachment is a message on its own');

    // The form must not refuse to submit with an empty body.
    assert.true(document.querySelector('form')?.checkValidity(), 'the browser would not block this');
  });

  // The direct-upload endpoint authenticates now, and
  // @rails/activestorage sends only its own headers unless it is handed
  // more. Miss that and every attachment fails at the first request —
  // which is exactly what happened when the endpoint moved.
  test('an attachment is uploaded with the token on it', async function (assert) {
    let authorization: string | null = null;
    let posted: string[] | null = null;
    let put = false;

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      // Active Storage's own shape, so a raw handler: it is a contract
      // with @rails/activestorage rather than one this API declares.
      mswHttp.post(ENV.directUploadURL, ({ request: req }) => {
        authorization = req.headers.get('Authorization');

        return HttpResponse.json({
          signed_id: 'signed-id',
          direct_upload: { url: 'https://storage.example.com/put', headers: {} },
        });
      }),

      mswHttp.put('https://storage.example.com/put', () => {
        put = true;

        return new HttpResponse(null, { status: 204 });
      }),

      http.post('/submission_requests/{submission_request_id}/messages', async ({ request: req, response }) => {
        posted = ((await req.json()) as { submission_message: { files: string[] } }).submission_message.files;

        return response(201).json({
          id: 9,
          body: '',
          author_role: 'submitter',
          author_uid: 'alice',
          created_at: now,
          read_at: null,
          files: [],
        });
      }),
    );

    await visit(`/requests/${request.id}`);

    const file = new File(['x'], 'samples.tsv', { type: 'text/tab-separated-values' });
    const transfer = new DataTransfer();
    transfer.items.add(file);

    const input = document.querySelector('input[type="file"]') as HTMLInputElement;
    input.files = transfer.files;

    await triggerEvent(input, 'change');
    await click('form button[type="submit"]');

    // The upload is an XHR that Ember's settledness does not know about,
    // so `click` returns before it has been through. Waiting here rather
    // than asserting straight away is what keeps the stubs in place
    // until it has — `resetHandlers` runs the moment this test body
    // ends, and anything still in flight then lands on the real network.
    await waitUntil(() => posted);

    // And then the rest of it. Posting refreshes the route and the
    // attention banner, which are issued after the POST resolves: on a
    // slower machine those land after the test body has finished, on
    // handlers that no longer exist and an owner that has been torn
    // down. `waitUntil` returns at the POST, so it is not enough on its
    // own.
    await settled();

    assert.strictEqual(authorization, 'Bearer test-token', 'the token went with the upload');
    assert.true(put, 'and the bytes went to storage');
    assert.deepEqual(posted, ['signed-id'], 'the signed id is what the message carries');
  });

  // The failure was recorded and never rendered: the button came back
  // and nothing else happened, which is what a lost message looks like.
  test('a send that fails says so', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      // Raw, not typed: the contract does not declare a 500 here, and
      // the point is what the screen does when one arrives anyway.
      mswHttp.post(`${ENV.apiURL}/submission_requests/${request.id}/messages`, () =>
        HttpResponse.json({ error: 'Internal server error' }, { status: 500 }),
      ),
    );

    await visit(`/requests/${request.id}`);
    await fillIn('[data-test-messages] textarea', 'Updated, please review.');
    await click('[data-test-messages] button[type="submit"]');

    assert.dom('[data-test-messages] [data-test-error]').exists();
  });

  test('renders the thread and posts a reply', async function (assert) {
    const initial: Message[] = [
      {
        id: 1,
        body: 'Please add an organism description.',
        author_role: 'curator',
        author_uid: 'alice',
        created_at: now,
        read_at: null,
        files: [],
      },
    ];

    const posted: Message = {
      id: 2,
      body: 'Updated, please review.',
      author_role: 'submitter',
      author_uid: 'bob',
      created_at: now,
      read_at: null,
      files: [],
    };

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => {
        return response(200).json(request);
      }),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(200).json(initial);
      }),

      http.post('/submission_requests/{submission_request_id}/messages', ({ response }) => {
        return response(201).json(posted);
      }),
    );

    await visit('/requests/1');

    // The status card dates the conversation without promising a reply time.
    assert.dom('[data-test-state]').includesText('last message 2025-01-02');
    assert.dom('[data-test-state]').doesNotIncludeText('business days');

    // Existing curator message renders with the labelled author.
    assert.dom('[data-test-messages] h2').includesText('Messages with the curator');
    assert.dom('[data-test-messages] li').exists({ count: 1 });
    assert.dom('[data-test-messages] li strong').hasText('DDBJ curator');
    assert.dom('[data-test-messages] li').includesText('Please add an organism description.');

    // Submit a reply and verify the optimistic append.
    await fillIn('section textarea', 'Updated, please review.');
    await click('section button[type="submit"]');

    assert.dom('[data-test-messages] li').exists({ count: 2 });
    assert.dom('[data-test-messages] li:nth-of-type(2) strong').hasText('You');
    assert.dom('[data-test-messages] li:nth-of-type(2)').includesText('Updated, please review.');
    // Textarea is cleared after a successful post.
    assert.dom('section textarea').hasValue('');
  });
});
