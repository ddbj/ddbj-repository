import { returnsNext, stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { _internals } from '../auth_command.ts';
import { runInContext } from './util.ts';

await snapshotTest({
  name: 'auth whoami',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify({ uid: 'alice', admin: false })),
      ],
    }, async () => {
      await mainCommand.parse(['auth', 'whoami']);
    });
  },
});

await snapshotTest({
  name: 'auth whoami; not logged in',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      apiKey: undefined,
    }, async () => {
      await mainCommand.parse(['auth', 'whoami']);
    });
  },
});

await snapshotTest({
  name: 'auth login API_KEY',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify({ uid: 'alice', admin: false })),
      ],
    }, async () => {
      await mainCommand.parse(['auth', 'login', 'API_KEY']);
    });
  },
});

await snapshotTest({
  name: 'auth login',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify({ login_url: 'http://example.com/login' })),
      ],
    }, async () => {
      // @ts-expect-error for test
      const keypressStub = stub(_internals, 'keypress', returnsNext([Promise.resolve({ key: 'a' })]));
      const openStub = stub(_internals, 'open', returnsNext([Promise.resolve()]));

      try {
        await mainCommand.parse(['auth', 'login']);
      } finally {
        keypressStub.restore();
        openStub.restore();
      }
    });
  },
});

await snapshotTest({
  name: 'auth logout',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({}, async () => {
      await mainCommand.parse(['auth', 'logout']);
    });
  },
});
