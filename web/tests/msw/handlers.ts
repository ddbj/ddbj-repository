import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';

import { http } from './http';

const directUploadURL = ENV.directUploadURL;
const diskURL = `${ENV.appURL}/rails/active_storage/disk/`;

export const handlers = [
  http.get('/me', ({ response }) => {
    return response(200).json({
      uid: 'test-user',
      api_key: 'test-api-key',
      admin: false,
    });
  }),

  // The attention banner refreshes on every navigation, so every
  // application test hits this; default to "nothing waiting" and let the
  // tests that care override it.
  http.get('/attention', ({ response }) => {
    return response(200).json({ requests: [], sets_waiting: 0 });
  }),

  // The request detail page offers "add to a set", which needs to know
  // which sets the reader is in; default to none so tests that don't
  // care about sets don't have to stub it.
  http.get('/sets', ({ response }) => {
    return response(200).json([]);
  }),

  // The set page loads the review-link state; default to disabled so the
  // tests that are about the roster or the submissions don't have to stub
  // it.
  http.get('/sets/{set_id}/reviewer_access', ({ response }) => {
    return response(200).json({ enabled: false, url: null, expires_at: null, expired: false, count: 0, others: 0 });
  }),

  // Both lists behind the link are their own routes, and both are empty
  // unless a test says otherwise.
  http.get('/sets/{set_id}/reviewer_access/accessions', ({ response }) => {
    return response(200).json([]);
  }),

  http.get('/sets/{set_id}/accessions', ({ response }) => {
    return response(200).json([]);
  }),

  // The set page renders the set's own thread; default to empty so the
  // tests that are about the roster or the submissions do not have to
  // stub a conversation.
  http.get('/sets/{set_id}/messages', ({ response }) => {
    return response(200).json([]);
  }),

  mswHttp.post(directUploadURL, () => {
    return HttpResponse.json({
      id: 1,
      key: 'test-key',
      filename: 'test.json',
      content_type: 'application/json',
      metadata: {},
      byte_size: 100,
      checksum: 'abc123',
      created_at: new Date().toISOString(),
      service_name: 'local',
      signed_id: 'test-signed-id',

      direct_upload: {
        url: `${diskURL}test`,
        headers: { 'Content-Type': 'application/json' },
      },
    });
  }),

  mswHttp.put(`${diskURL}*`, () => {
    return new HttpResponse(null, { status: 204 });
  }),
];
