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
      const readStub = stub(_internals, 'read', returnsNext(['API_KEY']));

      try {
        await mainCommand.parse(['auth', 'whoami']);
      } finally {
        readStub.restore();
      }
    });
  },
});

await snapshotTest({
  name: 'auth whoami; not logged in',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({}, async () => {
      const readStub = stub(_internals, 'read', returnsNext([undefined]));

      try {
        await mainCommand.parse(['auth', 'whoami']);
      } finally {
        readStub.restore();
      }
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
      const writeStub = stub(_internals, 'write', returnsNext([undefined]));

      try {
        await mainCommand.parse(['auth', 'login', 'API_KEY']);
      } finally {
        writeStub.restore();
      }
    });
  },
});

await snapshotTest({
  name: 'auth login; not logged in',
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
      // @ts-expect-error for test
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
      const removeStub = stub(_internals, 'remove', returnsNext([undefined]));

      try {
        await mainCommand.parse(['auth', 'logout']);
      } finally {
        removeStub.restore();
      }
    });
  },
});
