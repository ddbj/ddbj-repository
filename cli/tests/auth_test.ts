import { assertSpyCall, returnsNext, stub } from 'std/testing/mock.ts';
import type { Stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { _internals } from '../auth_command.ts';

async function runInContext(apiKey: string | undefined, responses: Response[], callback: (fetchStub: Stub) => Promise<void>) {
  const originalApiUrl = Deno.env.get('DDBJ_REPOSITORY_API_URL');
  Deno.env.set('DDBJ_REPOSITORY_API_URL', 'http://example.com/api');

  const readStub = stub(_internals, 'read', returnsNext([apiKey]));
  // @ts-expect-error
  const keypressStub = stub(_internals, 'keypress', returnsNext([Promise.resolve({ key: 'a' })]));
  // @ts-expect-error
  const openStub = stub(_internals, 'open', returnsNext([Promise.resolve()]));

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
    keypressStub.restore();
    openStub.restore();
    fetchStub.restore();
  }
}

await snapshotTest({
  name: 'auth whoami',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify({ uid: 'foo', admin: false })),
    ], async () => {
      await mainCommand.parse(['auth', 'whoami']);
    });
  },
});

await snapshotTest({
  name: 'auth whoami; not logged in',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext(undefined, [
    ], async () => {
      await mainCommand.parse(['auth', 'whoami']);
    });
  },
});

await snapshotTest({
  name: 'auth login API_KEY',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify({ uid: 'foo', admin: false })),
    ], async () => {
      await mainCommand.parse(['auth', 'login', 'API_KEY']);
    });
  },
});

await snapshotTest({
  name: 'auth login; not logged in',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext(undefined, [
      new Response(JSON.stringify({ login_url: 'http://example.com/login' })),
    ], async () => {
      await mainCommand.parse(['auth', 'login']);
    });
  },
});

await snapshotTest({
  name: 'auth logout',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
    ], async () => {
      await mainCommand.parse(['auth', 'logout']);
    });
  },
});
