import { module, test } from 'qunit';
import { visit, click } from '@ember/test-helpers';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type DownloadsService from 'repository/services/downloads';
import type ErrorModalService from 'repository/services/error-modal';
import type { components } from 'schema/openapi';

const now = '2025-01-01T00:00:00.000Z';

const request: components['schemas']['SubmissionRequest'] = {
  id: 42,
  db: 'st26',
  status: 'applied',
  error_code: null,
  error_message: null,
  created_at: now,
  closed_at: null,
  closable: false,
  sendable: false,
  send_blocked_reason: null,
  owned: true,
  owner_uid: 'test-user',
  processing: false,
  ddbj_record: { filename: 'upload.json', url: 'http://localhost:3000/api/submission_requests/42/files/ddbj_record' },
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
  last_message_at: null,
  sets: [],
  submission: null,
};

// Downloads go through a route that refuses a request carrying no
// credentials, and a browser cannot put a header on an anchor. The
// client therefore asks for the address and navigates to it — and the
// bit worth pinning is that it asks **with the token**, because that is
// the half that was missed when the endpoints moved.
module('Acceptance | downloading a file', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  test('asks for the address as an authenticated request, then goes there', async function (assert) {
    let authorization: string | null = null;
    let params: URLSearchParams | undefined;
    let went: string | undefined;

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      http.get('/submission_requests/{submission_request_id}/files/{name}', ({ request: req, response }) => {
        authorization = req.headers.get('Authorization');
        params = new URL(req.url).searchParams;

        return response(200).json({ url: 'https://storage.example.com/signed' });
      }),
    );

    // The service's own seam, not `window.location` — that is read-only.
    const downloads = this.owner.lookup('service:downloads') as DownloadsService;
    downloads.navigate = (url: string) => {
      went = url;
    };

    await visit('/requests/42');
    await click('[data-test-download]');

    assert.strictEqual(authorization, 'Bearer test-token', 'the token went with it');
    assert.strictEqual(params?.get('as'), 'url', 'asked for the address rather than the redirect');
    assert.strictEqual(params?.get('disposition'), 'attachment', 'and asked for it as a download');
    assert.strictEqual(went, 'https://storage.example.com/signed');
  });

  // The message belongs beside the file it is about. A modal over the
  // page saying the same thing hides the request the person was reading
  // and has to be dismissed before they can try the next file.
  test('a refusal is reported rather than swallowed, and only once', async function (assert) {
    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      http.get('/submission_requests/{submission_request_id}/files/{name}', ({ response }) => {
        return response(404).json({ error: 'Not found' });
      }),
    );

    await visit('/requests/42');
    await click('[data-test-download]');

    assert.dom('[data-test-error]').exists();

    const errorModal = this.owner.lookup('service:error-modal') as ErrorModalService;

    assert.strictEqual(errorModal.error, undefined, 'the modal was not also raised');
  });

  // An answer with no address in it is a failure however it was spelled.
  // Navigating to `undefined` would leave the app on a 404 page with
  // nothing to say what went wrong.
  test('an answer carrying no address is a failure, not a navigation', async function (assert) {
    let went: string | undefined;

    worker.use(
      http.get('/submission_requests/{id}', ({ response }) => response(200).json(request)),

      http.get('/submission_requests/{submission_request_id}/messages', ({ response }) => response(200).json([])),

      // Not the documented shape — which is the point.
      http.get('/submission_requests/{submission_request_id}/files/{name}', ({ response }) => {
        return response(200).json({} as { url: string });
      }),
    );

    const downloads = this.owner.lookup('service:downloads') as DownloadsService;
    downloads.navigate = (url: string) => {
      went = url;
    };

    await visit('/requests/42');
    await click('[data-test-download]');

    assert.strictEqual(went, undefined, 'nowhere to go, so it did not go');
    assert.dom('[data-test-error]').exists();
  });
});
