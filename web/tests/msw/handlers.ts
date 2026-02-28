import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';

import { http } from './http';

const directUploadURL = new URL('/rails/active_storage/direct_uploads', ENV.apiURL).toString();
const diskURL = new URL('/rails/active_storage/disk/', ENV.apiURL).toString();

export const handlers = [
  http.get('/me', ({ response }) => {
    return response(200).json({
      uid: 'test-user',
      api_key: 'test-api-key',
      admin: false,
    });
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
