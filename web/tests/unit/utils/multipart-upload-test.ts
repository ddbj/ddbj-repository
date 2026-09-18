import { module, test } from 'qunit';
import { setupTest } from 'repository/tests/helpers';

import SparkMD5 from 'spark-md5';
import { HttpResponse, http as mswHttp } from 'msw';

import uploadFile, { UploadRejected } from 'repository/utils/multipart-upload';

import { http } from '../../msw/http';
import { partURL, storeURL, upload } from '../../msw/handlers';
import { worker } from '../../msw/worker';

import type { RequestManager } from '@warp-drive/core';
import type { TestContext } from '@ember/test-helpers';

// Small enough to read in the assertions; the server decides this anyway.
const PART_SIZE = 8;

interface ReceivedPart {
  number: number;
  body: string;
}

module('Unit | Utility | multipart-upload', function (hooks) {
  setupTest(hooks);

  hooks.beforeEach(() => localStorage.clear());
  hooks.afterEach(() => localStorage.clear());

  function requestManager(context: TestContext) {
    return context.owner.lookup('service:request-manager') as RequestManager;
  }

  function file(contents: string, { name = 'reads.fastq', lastModified = 0 } = {}) {
    return new File([contents], name, { type: 'text/plain', lastModified });
  }

  // The same key the upload builds: what a File can be recognised by, plus a
  // hash of its ends (for a file this small, of the whole of it).
  function memoryKey(file: File, contents: string) {
    return `multipart-upload:${file.name}:${file.size}:${file.lastModified}:${SparkMD5.hash(contents)}`;
  }

  // The store, answering each part with the ETag the real one would — that
  // part's MD5 — and keeping what it was sent.
  function recordingStore(received: ReceivedPart[]) {
    return mswHttp.put(`${storeURL}part/:number`, async ({ request, params }) => {
      const body = await request.arrayBuffer();

      received.push({ number: Number(params['number']), body: new TextDecoder().decode(body) });

      return new HttpResponse(null, { status: 200, headers: { ETag: `"${SparkMD5.ArrayBuffer.hash(body)}"` } });
    });
  }

  function uploading(attributes = {}) {
    return upload({ state: 'uploading', part_size: PART_SIZE, ...attributes });
  }

  test('sends the file in the parts the server asked for, and completes with all of them', async function (assert) {
    const received: ReceivedPart[] = [];
    let completed: { part_number: number; etag: string }[] = [];

    worker.use(
      http.post('/uploads', ({ response }) => response(201).json(uploading({ part_count: 3 }))),
      http.post('/uploads/{token}/complete', async ({ request, response }) => {
        ({ parts: completed } = await request.json());

        return response(202).json(upload({ state: 'verifying' }));
      }),
      recordingStore(received),
    );

    const signedBlobId = await uploadFile(file('AAAAAAAABBBBBBBBCCCC'), { requestManager: requestManager(this) });

    assert.strictEqual(signedBlobId, 'test-signed-id');

    assert.deepEqual(
      received.sort((a, b) => a.number - b.number),
      [
        { number: 1, body: 'AAAAAAAA' },
        { number: 2, body: 'BBBBBBBB' },
        { number: 3, body: 'CCCC' },
      ],
      'every part, cut where the server said',
    );

    // Every part exactly once, in order, each with the ETag the store gave —
    // which is what the server refuses a completion for not having.
    assert.deepEqual(
      completed,
      received.map(({ number, body }) => ({ part_number: number, etag: SparkMD5.hash(body) })),
      'completed with all of the parts, in order',
    );
  });

  // The store refuses a part that arrived damaged rather than keeping it, so
  // the damage costs one part instead of a whole file read back on the server.
  test('sends each part with its MD5', async function (assert) {
    let header: string | null = null;

    worker.use(
      mswHttp.put(`${storeURL}part/:number`, async ({ request }) => {
        const body = await request.arrayBuffer();

        header = request.headers.get('Content-MD5');

        return new HttpResponse(null, { status: 200, headers: { ETag: `"${SparkMD5.ArrayBuffer.hash(body)}"` } });
      }),
    );

    await uploadFile(file('ACGT'), { requestManager: requestManager(this) });

    assert.strictEqual(header, base64OfHex(SparkMD5.hash('ACGT')));
  });

  test('a part that arrived as something else is sent again', async function (assert) {
    let attempts = 0;

    worker.use(
      mswHttp.put(`${storeURL}part/:number`, async ({ request }) => {
        const body = await request.arrayBuffer();
        const etag = ++attempts === 1 ? SparkMD5.hash('something else') : SparkMD5.ArrayBuffer.hash(body);

        return new HttpResponse(null, { status: 200, headers: { ETag: `"${etag}"` } });
      }),
    );

    const signedBlobId = await uploadFile(file('ACGT'), { requestManager: requestManager(this) });

    assert.strictEqual(signedBlobId, 'test-signed-id');
    assert.strictEqual(attempts, 2, 'sent again, rather than completed with a part the store does not hold');
  });

  // Why it is resumable: picking the same file again after an interruption
  // sends only what the store does not already have. The parts it has are
  // recognised by their MD5 — a copy that is not ours does not count.
  test('carries on an upload the store already has parts of', async function (assert) {
    const received: ReceivedPart[] = [];
    const carried = file('AAAAAAAABBBBBBBBCCCC');

    localStorage.setItem(memoryKey(carried, 'AAAAAAAABBBBBBBBCCCC'), 'test-token');

    let polls = 0;

    worker.use(
      http.get('/uploads/{token}', ({ response }) => {
        if (polls++ === 0) {
          return response(200).json(
            uploading({
              part_count: 3,
              parts: [{ part_number: 1, etag: `"${SparkMD5.hash('AAAAAAAA')}"`, size: PART_SIZE }],
            }),
          );
        }

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
      recordingStore(received),
    );

    await uploadFile(carried, { requestManager: requestManager(this) });

    assert.deepEqual(
      received.map((part) => part.number).sort(),
      [2, 3],
      'the part the store already holds is not sent again',
    );
  });

  test('a part the store holds that is not ours is sent again', async function (assert) {
    const received: ReceivedPart[] = [];
    const carried = file('AAAAAAAABBBBBBBB');

    localStorage.setItem(memoryKey(carried, 'AAAAAAAABBBBBBBB'), 'test-token');

    let polls = 0;

    worker.use(
      http.get('/uploads/{token}', ({ response }) => {
        if (polls++ === 0) {
          return response(200).json(
            uploading({
              part_count: 2,
              parts: [{ part_number: 1, etag: `"${SparkMD5.hash('not what we mean to send')}"`, size: PART_SIZE }],
            }),
          );
        }

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
      recordingStore(received),
    );

    await uploadFile(carried, { requestManager: requestManager(this) });

    assert.deepEqual(received.map((part) => part.number).sort(), [1, 2]);
  });

  // A spent URL cannot be sent to twice, so a part that has to go again asks
  // for a new one rather than reusing the one it just failed with.
  test('a part that failed is sent again with a fresh URL', async function (assert) {
    const asked: number[][] = [];
    let attempts = 0;

    worker.use(
      http.post('/uploads/{token}/part_urls', async ({ request, response }) => {
        const { part_numbers } = await request.json();

        asked.push(part_numbers);

        return response(200).json(part_numbers.map((part_number) => ({ part_number, url: partURL(part_number) })));
      }),
      mswHttp.put(`${storeURL}part/:number`, async ({ request }) => {
        const body = await request.arrayBuffer();

        if (++attempts === 1) return new HttpResponse(null, { status: 403 });

        return new HttpResponse(null, { status: 200, headers: { ETag: `"${SparkMD5.ArrayBuffer.hash(body)}"` } });
      }),
    );

    await uploadFile(file('ACGT'), { requestManager: requestManager(this) });

    assert.deepEqual(asked, [[1], [1]], 'asked again rather than sending to the URL that just failed');
  });

  // Rejected means this token cannot go anywhere. Starting over is what the
  // reader asked for by choosing the file again.
  test('a remembered upload the server has rejected is started over', async function (assert) {
    const sending = file('ACGT');
    let started = 0;

    localStorage.setItem(memoryKey(sending, 'ACGT'), 'rejected-token');

    let polls = 0;

    worker.use(
      http.post('/uploads', ({ response }) => {
        started++;

        return response(201).json(uploading());
      }),
      http.get('/uploads/{token}', ({ response }) => {
        if (polls++ === 0) return response(200).json(upload({ state: 'rejected' }));

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
    );

    assert.strictEqual(await uploadFile(sending, { requestManager: requestManager(this) }), 'test-signed-id');
    assert.strictEqual(started, 1, 'sent again from the start');
  });

  // Sent by an earlier attempt but never verified: the parts are all there, so
  // completing again is what queues the verification afresh.
  test('a remembered upload that was already sent is completed again, not resent', async function (assert) {
    const received: ReceivedPart[] = [];
    const carried = file('AAAAAAAABBBBBBBB');
    let completed: { part_number: number; etag: string }[] = [];
    let polls = 0;

    localStorage.setItem(memoryKey(carried, 'AAAAAAAABBBBBBBB'), 'test-token');

    worker.use(
      http.get('/uploads/{token}', ({ response }) => {
        if (polls++ === 0)
          return response(200).json(upload({ state: 'verifying', part_size: PART_SIZE, part_count: 2 }));

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
      http.post('/uploads/{token}/complete', async ({ request, response }) => {
        ({ parts: completed } = await request.json());

        return response(202).json(upload({ state: 'verifying' }));
      }),
      recordingStore(received),
    );

    await uploadFile(carried, { requestManager: requestManager(this) });

    assert.deepEqual(received, [], 'nothing was sent again');

    assert.deepEqual(
      completed,
      [
        { part_number: 1, etag: SparkMD5.hash('AAAAAAAA') },
        { part_number: 2, etag: SparkMD5.hash('BBBBBBBB') },
      ],
      'completed again with the ETags worked out here',
    );
  });

  // The file is sitting complete in the store; a busy moment while asking
  // about it is not a reason to throw away the only handle on it.
  test('a poll that fails is asked again, and the upload is still remembered', async function (assert) {
    const sending = file('ACGT');
    let polls = 0;

    worker.use(
      http.get('/uploads/{token}', ({ response }) => {
        if (polls++ === 0) return response(503).json({ error: 'the store is busy' });

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
    );

    assert.strictEqual(await uploadFile(sending, { requestManager: requestManager(this) }), 'test-signed-id');
    assert.strictEqual(polls, 2, 'asked again');
    assert.strictEqual(localStorage.getItem(memoryKey(sending, 'ACGT')), null);
  });

  // Private browsing, or site data blocked: an upload that refused to run
  // there would be an upload nobody could make.
  test('an upload runs where storage is not available', async function (assert) {
    const storage = Storage.prototype;
    const setItem = storage.setItem.bind(storage);

    storage.setItem = () => {
      throw new DOMException('quota', 'QuotaExceededError');
    };

    try {
      assert.strictEqual(
        await uploadFile(file('ACGT'), { requestManager: requestManager(this) }),
        'test-signed-id',
        'the file still goes up; only carrying it on is lost',
      );
    } finally {
      storage.setItem = setItem;
    }
  });

  test('says so when the store did not keep the file', async function (assert) {
    worker.use(http.get('/uploads/{token}', ({ response }) => response(200).json(upload({ state: 'rejected' }))));

    await assert.rejects(
      uploadFile(file('ACGT'), { requestManager: requestManager(this) }),
      UploadRejected,
      'the reader is told, rather than left waiting at 100%',
    );
  });

  test('remembers the upload while it is going and forgets it once it is verified', async function (assert) {
    const sending = file('ACGT');

    worker.use(
      http.get('/uploads/{token}', ({ response }) => {
        assert.strictEqual(
          localStorage.getItem(memoryKey(sending, 'ACGT')),
          'test-token',
          'remembered while it is going',
        );

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
    );

    await uploadFile(sending, { requestManager: requestManager(this) });

    assert.strictEqual(localStorage.getItem(memoryKey(sending, 'ACGT')), null, 'forgotten once there is a Blob');
  });

  // A token from an upload the server no longer has: start again rather than
  // fail, which is what a reader picking the file again expects to happen.
  test('a token the server no longer knows starts a new upload', async function (assert) {
    const sending = file('ACGT');
    let started = 0;

    localStorage.setItem(memoryKey(sending, 'ACGT'), 'gone');

    worker.use(
      http.get('/uploads/{token}', ({ params, response }) => {
        if (params.token === 'gone') return response(404).json({ error: 'not found' });

        return response(200).json(upload({ state: 'ready', signed_blob_id: 'test-signed-id' }));
      }),
      http.post('/uploads', ({ response }) => {
        started++;

        return response(201).json(uploading());
      }),
    );

    assert.strictEqual(await uploadFile(sending, { requestManager: requestManager(this) }), 'test-signed-id');
    assert.strictEqual(started, 1);
  });

  test('reports how far it has got', async function (assert) {
    const seen: number[] = [];

    worker.use(http.post('/uploads', ({ response }) => response(201).json(uploading({ part_count: 2 }))));

    await uploadFile(file('AAAAAAAABBBBBBBB'), {
      requestManager: requestManager(this),
      onProgress: ({ sent, total }) => {
        assert.strictEqual(total, 16);

        seen.push(sent);
      },
    });

    assert.strictEqual(seen.at(-1), 16, 'the last word is the whole file');
  });

  test('asks for part URLs in batches the server will sign', async function (assert) {
    const asked: number[][] = [];

    worker.use(
      http.post('/uploads', ({ response }) => response(201).json(uploading({ part_size: 1, part_count: 150 }))),
      http.post('/uploads/{token}/part_urls', async ({ request, response }) => {
        const { part_numbers } = await request.json();

        asked.push(part_numbers);

        return response(200).json(part_numbers.map((part_number) => ({ part_number, url: partURL(part_number) })));
      }),
    );

    await uploadFile(file('A'.repeat(150)), { requestManager: requestManager(this) });

    assert.deepEqual(
      asked.map((batch) => batch.length),
      [100, 50],
    );
  });
});

function base64OfHex(hex: string) {
  return btoa(String.fromCharCode(...(hex.match(/../g) ?? []).map((pair) => parseInt(pair, 16))));
}
