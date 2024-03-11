import { assertSpyCall } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { runInContext } from './util.ts';

import validations1 from './fixtures/validations-1.json' with { type: 'json' };
import validations2 from './fixtures/validations-2.json' with { type: 'json' };

await snapshotTest({
  name: 'validation create jvar',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(new File(['foo'], 'path/to/file')), // in createValidation
        new Response(JSON.stringify(validations1[0])), // in createValidation
        new Response(JSON.stringify(validations1[0])), // in waitForRequestFinished
      ],
    }, async () => {
      await mainCommand.parse(['validation', 'create', 'jvar', '--excel.file=path/to/file']);
    });
  },
});

await snapshotTest({
  name: 'valiadation list',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(validations1), {
          headers: {
            Link: '<http://example.com/api/validations?page=2>; rel="next"',
          },
        }),

        new Response(JSON.stringify(validations2)),
      ],
    }, async () => {
      await mainCommand.parse(['validation', 'list']);
    });
  },
});

await snapshotTest({
  name: 'validation show 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(validations1[0])),
      ],
    }, async () => {
      await mainCommand.parse(['validation', 'show', '1']);
    });
  },
});

await snapshotTest({
  name: 'validation show 2',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(validations2[0])),
      ],
    }, async () => {
      await mainCommand.parse(['validation', 'show', '2']);
    });
  },
});

await snapshotTest({
  name: 'validation get-file 1 path/to/file',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response('foo'),
      ],
    }, async (fetchStub) => {
      await mainCommand.parse(['validation', 'get-file', '1', 'path/to/file']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://example.com/api/validations/1/files/path/to/file', {
          headers: { 'Authorization': 'Bearer API_KEY' },
        }],
      });
    });
  },
});

await snapshotTest({
  name: 'validation cancel 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(validations1[0])),
      ],
    }, async (fetchStub) => {
      await mainCommand.parse(['validation', 'cancel', '1']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://example.com/api/validations/1', {
          method: 'DELETE',
          headers: { 'Authorization': 'Bearer API_KEY' },
        }],
      });
    });
  },
});
