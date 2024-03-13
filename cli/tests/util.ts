import { returnsNext, stub } from 'std/testing/mock.ts';

import { _internals } from '../api_key.ts';

import type { Stub } from 'std/testing/mock.ts';

export async function runInContext(opts: { apiKey?: string; responses?: Response[] } = {}, callback: (fetchStub: Stub) => Promise<void>) {
  const apiKey = Object.hasOwn(opts, 'apiKey') ? opts.apiKey : 'API_KEY';
  const responses = opts.responses ?? [];

  const originalApiUrl = Deno.env.get('DDBJ_REPOSITORY_API_URL');
  Deno.env.set('DDBJ_REPOSITORY_API_URL', 'http://example.com/api');

  const readStub = stub(_internals, 'read', returnsNext([apiKey]));
  const writeStub = stub(_internals, 'write', returnsNext([undefined]));
  const removeStub = stub(_internals, 'remove', returnsNext([undefined]));

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
    writeStub.restore();
    removeStub.restore();
    fetchStub.restore();
  }
}
