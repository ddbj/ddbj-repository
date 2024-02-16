import { assertSpyCall, returnsNext, stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { _internals } from '../util.ts';

import validations1 from './fixtures/validations-1.json' with { type: 'json' };
import validations2 from './fixtures/validations-2.json' with { type: 'json' };

await snapshotTest({
  name: 'valiadation list',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    const readStub = stub(_internals, 'read', returnsNext(['dummy']));

    const fetchStub = stub(
      globalThis,
      'fetch',
      returnsNext([
        Promise.resolve(
          new Response(JSON.stringify(validations1), {
            headers: {
              Link: '<http://localhost:3000/api/validations?page=2>; rel="next"',
            },
          }),
        ),

        Promise.resolve(new Response(JSON.stringify(validations2))),
      ]),
    );

    try {
      await mainCommand.parse(['validation', 'list']);
    } finally {
      readStub.restore();
      fetchStub.restore();
    }
  },
});

await snapshotTest({
  name: 'validation show 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    const readStub = stub(_internals, 'read', returnsNext(['dummy']));

    const fetchStub = stub(
      globalThis,
      'fetch',
      returnsNext([
        Promise.resolve(new Response(JSON.stringify(validations1[0]))),
      ]),
    );

    try {
      await mainCommand.parse(['validation', 'show', '1']);
    } finally {
      readStub.restore();
      fetchStub.restore();
    }
  },
});

await snapshotTest({
  name: 'validation show 2',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    const readStub = stub(_internals, 'read', returnsNext(['dummy']));

    const fetchStub = stub(
      globalThis,
      'fetch',
      returnsNext([
        Promise.resolve(new Response(JSON.stringify(validations2[0]))),
      ]),
    );

    try {
      await mainCommand.parse(['validation', 'show', '2']);
    } finally {
      readStub.restore();
      fetchStub.restore();
    }
  },
});

await snapshotTest({
  name: 'validation get-file 1 dummy-path',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    const readStub = stub(_internals, 'read', returnsNext(['dummy']));

    const fetchStub = stub(
      globalThis,
      'fetch',
      returnsNext([
        Promise.resolve(new Response('dummy-file')),
      ]),
    );

    try {
      await mainCommand.parse(['validation', 'get-file', '1', 'dummy-path']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://localhost:3000/api/validations/1/files/dummy-path', {
          headers: {'Authorization': 'Bearer dummy' },
        }],
      })
    } finally {
      readStub.restore();
      fetchStub.restore();
    }
  }
})
