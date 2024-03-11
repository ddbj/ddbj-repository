import { returnsNext, stub } from 'std/testing/mock.ts';

import { _internals } from '../util.ts';

import type { Stub } from 'std/testing/mock.ts';

export async function runInContext(opts: { apiKey?: string; responses?: Response[] } = {}, callback: (fetchStub: Stub) => Promise<void>) {
  const apiKey = opts.apiKey ?? 'API_KEY';
  const responses = opts.responses ?? [];

  const originalApiUrl = Deno.env.get('DDBJ_REPOSITORY_API_URL');
  Deno.env.set('DDBJ_REPOSITORY_API_URL', 'http://example.com/api');

  const readStub = stub(_internals, 'read', returnsNext([apiKey]));

  const fetchStub = stub(
    globalThis,
    'fetch',
    returnsNext(responses.map((response) => Promise.resolve(response))),
  );

  try {
    await callback(fetchStub);
  } finally {
    if (originalApiUrl) {
      Deno.env.set('DDBJ_REPOSITORY_API_URL', originalApiUrl);
    }

    readStub.restore();
    fetchStub.restore();
  }
}
