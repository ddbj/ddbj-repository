import { assertSpyCall, returnsNext, stub } from 'std/testing/mock.ts';
import type { Stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { _internals } from '../util.ts';

import submissions1 from './fixtures/submissions-1.json' with { type: 'json' };
import submissions2 from './fixtures/submissions-2.json' with { type: 'json' };

async function runInContext(apiKey: string, responses: Response[], callback: (fetchStub: Stub) => Promise<void>) {
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

await snapshotTest({
  name: 'submission create 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(submissions1[0])),
    ], async (fetchStub) => {
      await mainCommand.parse(['submission', 'create', '1']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://example.com/api/submissions/', {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer dummy',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ validation_id: 1 }),
        }],
      });
    });
  },
});

await snapshotTest({
  name: 'submission list',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(submissions1), {
        headers: {
          Link: '<http://example.com/api/submissions?page=2>; rel="next"',
        },
      }),

      new Response(JSON.stringify(submissions2)),
    ], async () => {
      await mainCommand.parse(['submission', 'list']);
    });
  },
});

await snapshotTest({
  name: 'submission show X-1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(submissions1[0])),
    ], async () => {
      await mainCommand.parse(['submission', 'show', 'X-1']);
    });
  },
});
