import { assertSpyCall, returnsNext, stub } from 'std/testing/mock.ts';
import type { Stub } from 'std/testing/mock.ts';

import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from '../main_command.ts';
import { runInContext } from './util.ts';

import submissions1 from './fixtures/submissions-1.json' with { type: 'json' };
import submissions2 from './fixtures/submissions-2.json' with { type: 'json' };

await snapshotTest({
  name: 'submission create 1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(submissions1[0])),
      ]
    }, async (fetchStub) => {
      await mainCommand.parse(['submission', 'create', '1']);

      assertSpyCall(fetchStub, 0, {
        args: ['http://example.com/api/submissions/', {
          method: 'POST',
          headers: {
            'Authorization': 'Bearer API_KEY',
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
    await runInContext({
      responses: [
        new Response(JSON.stringify(submissions1), {
          headers: {
            Link: '<http://example.com/api/submissions?page=2>; rel="next"',
          },
        }),

        new Response(JSON.stringify(submissions2)),
      ]
    }, async () => {
      await mainCommand.parse(['submission', 'list']);
    });
  },
});

await snapshotTest({
  name: 'submission show X-1',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(submissions1[0])),
      ]
    }, async () => {
      await mainCommand.parse(['submission', 'show', 'X-1']);
    });
  },
});

await snapshotTest({
  name: 'submission get-file X-1 path/to/file',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await runInContext({
      responses: [
        new Response(JSON.stringify(submissions1[0])),
        new Response('foo'),
      ]
    }, async (fetchStub) => {
      await mainCommand.parse(['submission', 'get-file', 'X-1', 'path/to/file']);

      assertSpyCall(fetchStub, 1, {
        args: ['http://example.com/api/validations/1/files/path/to/file', {
          headers: { 'Authorization': 'Bearer API_KEY' },
        }],
      });
    });
  },
});
