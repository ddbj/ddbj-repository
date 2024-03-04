import { assertSpyCall, returnsNext, stub } from 'std/testing/mock.ts';
import type { Stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import validationCreateCommand from '../validation_create_command.ts';
import { _internals } from '../util.ts';

import validations1 from './fixtures/validations-1.json' with { type: 'json' };
import validations2 from './fixtures/validations-2.json' with { type: 'json' };

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
  name: 'validation create jvar',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(new File(['foo'], 'foo.txt')), // in createValidation
      new Response(JSON.stringify(validations1[0])), // in createValidation
      new Response(JSON.stringify(validations1[0])), // in waitForRequestFinished
    ], async () => {
      await mainCommand.parse(['validation', 'create', 'jvar', '--excel.file=tests/fixtures/validations-2.json']);
    });
  },
});

await snapshotTest({
  name: 'valiadation list',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(validations1), {
        headers: {
          Link: '<http://example.com/api/validations?page=2>; rel="next"',
        },
      }),

      new Response(JSON.stringify(validations2)),
    ], async () => {
      await mainCommand.parse(['validation', 'list']);
    });
  },
});

await snapshotTest({
  name: 'validation show 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(validations1[0])),
    ], async () => {
      await mainCommand.parse(['validation', 'show', '1']);
    });
  },
});

await snapshotTest({
  name: 'validation show 2',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response(JSON.stringify(validations2[0])),
    ], async () => {
      await mainCommand.parse(['validation', 'show', '2']);
    });
  },
});

await snapshotTest({
  name: 'validation get-file 1 dummy-path',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext('dummy', [
      new Response('dummy-file'),
    ], async (fetchStub) => {
      await mainCommand.parse(['validation', 'get-file', '1', 'dummy-path']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://example.com/api/validations/1/files/dummy-path', {
          headers: { 'Authorization': 'Bearer dummy' },
        }],
      });
    });
  },
});
