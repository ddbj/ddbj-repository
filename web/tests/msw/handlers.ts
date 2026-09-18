import { HttpResponse, http as mswHttp } from 'msw';
import SparkMD5 from 'spark-md5';

import ENV from 'repository/config/environment';

import { http } from './http';

import type { components } from 'schema/openapi';

type Upload = components['schemas']['Upload'];

const directUploadURL = ENV.directUploadURL;
const diskURL = `${ENV.appURL}/rails/active_storage/disk/`;

// The object store, as far as these tests are concerned: it answers a part
// with the ETag the real one would, which is that part's MD5.
export const storeURL = `${ENV.appURL}/test-store/`;

export function partURL(number: number) {
  return `${storeURL}part/${number}`;
}

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

  // Data files go up in parts. One part by default — a test that cares about
  // several says so.
  http.post('/uploads', ({ response }) => {
    return response(201).json(upload({ state: 'uploading' }));
  }),

  http.post('/uploads/{token}/part_urls', async ({ request, response }) => {
    const { part_numbers } = await request.json();

    return response(200).json(part_numbers.map((part_number) => ({ part_number, url: partURL(part_number) })));
  }),

  http.post('/uploads/{token}/complete', ({ response }) => {
    return response(202).json(upload({ state: 'verifying' }));
  }),

  http.get('/uploads/{token}', ({ response }) => {
    return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
  }),

  mswHttp.put(`${storeURL}part/:number`, async ({ request }) => {
    const md5 = SparkMD5.ArrayBuffer.hash(await request.arrayBuffer());

    return new HttpResponse(null, { status: 200, headers: { ETag: `"${md5}"` } });
  }),
];

export function upload(attributes: Partial<Upload> = {}): Upload {
  return {
    token: 'test-token',
    state: 'uploading',
    part_size: 16 * 1024 * 1024,
    part_count: 1,
    parts: [],
    signed_blob_id: null,
    ...attributes,
  };
}
