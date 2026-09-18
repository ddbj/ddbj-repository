import SparkMD5 from 'spark-md5';

import type { RequestManager } from '@warp-drive/core';
import type { components } from 'schema/openapi';

type Upload = components['schemas']['Upload'];

// Data files go to the store in parts (`/api/uploads`), not in one PUT. A
// browser sending tens of GB down a hotel connection will be interrupted; with
// parts, what an interruption costs is one part, and what the store already
// has is the client's to ask for. Everything else — message attachments and
// the like — stays on Active Storage's direct upload.
//
// The whole file's MD5 is never computed here. Each part carries its own, which
// the store checks on arrival and returns as the part's ETag; what the server
// then reads back is the file this browser sent, part by part. Hashing every
// byte a second time, in order, to declare a checksum the server computes
// anyway would only slow down the upload it is meant to protect.

// How many parts are in the air at once. Enough to fill a fast link, few
// enough that a phone does not hold four 16 MiB parts in memory at a time.
const CONCURRENCY = 3;

// The server signs at most 100 part URLs per request.
const URLS_PER_REQUEST = 100;

// Each part is tried this many times before the upload gives up, waiting a
// little longer each time. A part URL expires in an hour and the store can
// refuse one under load; both are answered by asking for a new URL and sending
// the part again. About a minute and a half of patience per part — the reader
// is watching this, so it cannot be the CLI's half hour.
const ATTEMPTS_PER_PART = 6;
const RETRY_WAIT = 2000;
const MAX_RETRY_WAIT = 30000;

const POLL_INTERVAL = 2000;

// How many polls in a row may fail before the upload gives up. The server can
// answer 503 while the store is busy, and a laptop can lose its network for a
// minute; neither says anything about the file, which is sitting complete in
// the store.
const POLL_FAILURES = 10;

// Where a half-finished upload is remembered, so that picking the same file
// again carries it on rather than starting over. The file itself cannot be
// remembered — a browser will not hand back a file the reader has not just
// chosen — so this is keyed by what a File can be recognised by, plus a hash of
// its first and last megabyte. Name, size and mtime alone can be the same for
// two different files, and what a wrong match would attach to the submission is
// the other file.
const MEMORY_PREFIX = 'multipart-upload:';

const SAMPLE = 1024 * 1024;

export class UploadRejected extends Error {}

export class PartMismatch extends Error {}

export interface Progress {
  sent: number;
  total: number;

  // `verifying` is the server reading the finished object through to compute
  // its checksum — minutes, for a large file, with nothing left to send. It is
  // reported here because only this knows when sending ended: a caller that
  // guessed would put the wrong words on the screen for the longest part of
  // the wait.
  state: 'uploading' | 'verifying';
}

export interface Options {
  requestManager: RequestManager;
  onProgress?: (progress: Progress) => void;
  signal?: AbortSignal;
}

// Sends the file and answers with the signed blob id that names it, once the
// server has read the finished object through and made it a Blob.
export default async function uploadFile(file: File, options: Options): Promise<string> {
  const upload = new MultipartUpload(file, options);

  return upload.perform();
}

class MultipartUpload {
  #file: File;
  #options: Options;

  // Per part, because parts are in the air together: one running total would
  // be overwritten by whichever part reported last.
  #sent = new Map<number, number>();

  #state: Progress['state'] = 'uploading';

  #cachedKey?: string;

  constructor(file: File, options: Options) {
    this.#file = file;
    this.#options = options;
  }

  async perform() {
    let upload = await this.#resume();

    if (!upload) {
      upload = await this.#start();

      await this.#remember(upload.token);
    }

    if (upload.state === 'uploading') {
      const etags = await this.#sendParts(upload);

      await this.#complete(upload, etags);
    } else if (upload.state === 'verifying') {
      // Sent by an earlier attempt but not verified. Completing again is what
      // queues the verification afresh — waiting alone would wait for a run
      // that may have failed. The ETags are each part's MD5, so they can be
      // worked out here rather than asked for.
      await this.#complete(upload, await this.#partEtags(upload));
    }

    this.#state = 'verifying';
    this.#report();

    const signedBlobId = await this.#waitUntilReady(upload);

    // Only now: until there is a Blob, this token is the only handle on what
    // has been sent. A failed poll keeps it, so choosing the file again waits
    // for the same upload instead of sending it all over again.
    await this.#forget();

    return signedBlobId;
  }

  // What an earlier attempt left, if the store still has it. A token the
  // server no longer knows, or an upload it has rejected, is forgotten here
  // and the file is sent again from the start.
  async #resume() {
    const token = await this.#remembered();

    if (!token) return null;

    try {
      const upload = await this.#get(token);

      if (upload.state !== 'rejected') return upload;
    } catch (e) {
      if (!isNotFound(e)) throw e;
    }

    await this.#forget();

    return null;
  }

  async #start() {
    const { content } = await this.#options.requestManager.request<Upload>({
      url: '/uploads',
      method: 'POST',
      // Refusals belong on this screen, beside the file that was chosen — not
      // in the modal the rest of the app uses for errors nobody asked for.
      options: { reportErrors: false },
      data: {
        upload: {
          filename: this.#file.name,
          content_type: this.#file.type || 'application/octet-stream',
          byte_size: this.#file.size,
        },
      },
    });

    return content;
  }

  // Only the parts the store does not already hold. A part it holds is known
  // to be ours by its ETag, which is that part's MD5 — a part sent twice is
  // listed once per copy, and the copy that matches is the one this browser
  // meant to send.
  async #sendParts(upload: Upload) {
    const etags = await this.#storedParts(upload);
    const missing = partNumbers(upload).filter((number) => !etags.has(number));

    // What the store already holds counts as sent: the bar is about the file,
    // not about this attempt.
    for (const number of etags.keys()) this.#sent.set(number, this.#partSize(upload, number));

    this.#report();

    for (const batch of chunk(missing, URLS_PER_REQUEST)) {
      const urls = await this.#partURLs(upload, batch);

      await inParallel(batch, CONCURRENCY, async (number) => {
        etags.set(number, await this.#sendPart(upload, number, urls.get(number)));
      });
    }

    return etags;
  }

  async #storedParts(upload: Upload) {
    const etags = new Map<number, string>();

    for (const part of upload.parts) {
      const etag = unquote(part.etag);

      if (etag === (await this.#partMD5(upload, part.part_number))) etags.set(part.part_number, etag);
    }

    return etags;
  }

  async #sendPart(upload: Upload, number: number, signed?: string): Promise<string> {
    // The batch of URLs is spent one at a time: they last an hour, and a part
    // that has to be sent again may well be past that.
    let url = signed;

    for (let attempt = 1; ; attempt++) {
      url ||= (await this.#partURLs(upload, [number])).get(number);

      if (!url) throw new Error(`The server did not sign part ${number}.`);

      const body = this.#part(upload, number);
      const md5 = await md5Of(body);

      try {
        const etag = unquote(
          await put(url, body, {
            md5,
            signal: this.#options.signal,
            onProgress: (sent) => {
              this.#sent.set(number, sent);
              this.#report();
            },
          }),
        );

        // The store's ETag for a part is that part's MD5. Anything else means
        // what arrived is not what was sent, and sending it again is the
        // answer — not carrying on and having the server read the whole file
        // before refusing it.
        if (etag !== md5) throw new PartMismatch(`part ${number} arrived as ${etag}`);

        this.#sent.set(number, body.size);
        this.#report();

        return etag;
      } catch (e) {
        this.#sent.delete(number);

        if (isAborted(e) || attempt === ATTEMPTS_PER_PART) throw e;

        url = undefined;

        await delay(Math.min(attempt * RETRY_WAIT, MAX_RETRY_WAIT), this.#options.signal);
      }
    }
  }

  async #partEtags(upload: Upload) {
    const etags = new Map<number, string>();

    for (const number of partNumbers(upload)) etags.set(number, await this.#partMD5(upload, number));

    return etags;
  }

  async #partMD5(upload: Upload, number: number) {
    return md5Of(this.#part(upload, number));
  }

  #part(upload: Upload, number: number) {
    return this.#file.slice((number - 1) * upload.part_size, number * upload.part_size);
  }

  #partSize(upload: Upload, number: number) {
    return this.#part(upload, number).size;
  }

  async #partURLs(upload: Upload, numbers: number[]) {
    const { content } = await this.#options.requestManager.request<{ part_number: number; url: string }[]>({
      url: `/uploads/${encodeURIComponent(upload.token)}/part_urls`,
      method: 'POST',
      options: { reportErrors: false },
      data: { part_numbers: numbers },
    });

    return new Map(content.map(({ part_number, url }) => [part_number, url]));
  }

  async #complete(upload: Upload, etags: Map<number, string>) {
    const parts = [...etags].sort(([a], [b]) => a - b).map(([part_number, etag]) => ({ part_number, etag }));

    await this.#options.requestManager.request({
      url: `/uploads/${encodeURIComponent(upload.token)}/complete`,
      method: 'POST',
      options: { reportErrors: false },
      data: { parts },
    });
  }

  // The server reads the finished object through to compute its checksum — a
  // multipart ETag is not the MD5 of the file — and only then is there a Blob
  // to attach. Minutes, for a file of tens of GB.
  async #waitUntilReady(upload: Upload) {
    let failures = 0;

    for (;;) {
      try {
        const current = await this.#get(upload.token);

        failures = 0;

        if (current.state === 'ready') return current.signed_blob_id!;

        if (current.state === 'rejected') {
          await this.#forget();

          throw new UploadRejected('The store did not keep the file. Try uploading it again.');
        }
      } catch (e) {
        // The store being busy (503) or a moment without a network is not an
        // answer about the file. Asking again costs one request; giving up
        // costs everything that was sent.
        if (e instanceof UploadRejected || isAborted(e) || ++failures > POLL_FAILURES) throw e;
      }

      await delay(POLL_INTERVAL, this.#options.signal);
    }
  }

  async #get(token: string) {
    const { content } = await this.#options.requestManager.request<Upload>({
      url: `/uploads/${encodeURIComponent(token)}`,
      options: { reportErrors: false },
    });

    return content;
  }

  #report() {
    const sent = [...this.#sent.values()].reduce((total, bytes) => total + bytes, 0);

    this.#options.onProgress?.({
      sent: Math.min(sent, this.#file.size),
      total: this.#file.size,
      state: this.#state,
    });
  }

  async #key() {
    return (this.#cachedKey ??= await this.#buildKey());
  }

  async #buildKey() {
    const { name, size, lastModified } = this.#file;
    const ends =
      size <= 2 * SAMPLE ? this.#file : new Blob([this.#file.slice(0, SAMPLE), this.#file.slice(size - SAMPLE)]);

    return `${MEMORY_PREFIX}${name}:${size}:${lastModified}:${await md5Of(ends)}`;
  }

  // Storage is a convenience, never a condition: a browser in private mode, or
  // one with site data blocked, throws on every one of these, and an upload
  // that refused to run there would be an upload nobody could make.
  async #remembered() {
    try {
      return localStorage.getItem(await this.#key());
    } catch {
      return null;
    }
  }

  async #remember(token: string) {
    try {
      localStorage.setItem(await this.#key(), token);
    } catch {
      // Then this upload cannot be carried on. It can still be made.
    }
  }

  async #forget() {
    try {
      localStorage.removeItem(await this.#key());
    } catch {
      // See #remember.
    }
  }
}

// XHR and not fetch: only XHR reports how much of a request body has gone,
// and a file of tens of GB with no progress is a page that looks broken.
function put(
  url: string,
  body: Blob,
  { md5, signal, onProgress }: { md5: string; signal?: AbortSignal; onProgress: (sent: number) => void },
) {
  return new Promise<string>((resolve, reject) => {
    // XHR, and not the RequestManager: only XHR reports how much of a request
    // body has gone, and a file of tens of GB with no progress is a page that
    // looks broken. This request is to the object store, not to the API, so it
    // carries none of the handlers' concerns (no session, no base URL, no
    // JSON) — which is the other half of why it does not belong in the chain.
    // eslint-disable-next-line warp-drive/no-external-request-patterns
    const xhr = new XMLHttpRequest();

    xhr.open('PUT', url, true);
    xhr.setRequestHeader('Content-MD5', btoa(hexToBinary(md5)));

    xhr.upload.addEventListener('progress', (e) => onProgress(e.loaded));

    xhr.addEventListener('load', () => {
      if (xhr.status < 200 || xhr.status >= 300) {
        reject(new Error(`The store refused a part (${xhr.status}).`));

        return;
      }

      const etag = xhr.getResponseHeader('ETag');

      // Not a mismatch — a part that cannot be checked at all. The store sends
      // ETag and says so in Access-Control-Expose-Headers; a deployment where
      // it does not would otherwise look like every part arriving damaged.
      if (etag) {
        resolve(etag);
      } else {
        reject(new Error('The store did not say what it received (no ETag). Its CORS settings may not expose it.'));
      }
    });

    xhr.addEventListener('error', () => reject(new Error('The store could not be reached.')));
    xhr.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));

    signal?.addEventListener('abort', () => xhr.abort(), { once: true });

    xhr.send(body);
  });
}

// In chunks, because a part is as large as the server says: past 16 MiB it is
// still one Blob, and `arrayBuffer()` on a multi-GB one throws.
const HASH_CHUNK = 4 * 1024 * 1024;

async function md5Of(blob: Blob) {
  const spark = new SparkMD5.ArrayBuffer();

  for (let start = 0; start < blob.size; start += HASH_CHUNK) {
    spark.append(await blob.slice(start, start + HASH_CHUNK).arrayBuffer());
  }

  return spark.end();
}

function partNumbers(upload: Upload) {
  return Array.from({ length: upload.part_count }, (_, i) => i + 1);
}

function chunk<T>(items: T[], size: number) {
  return Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size));
}

// Workers over one list, rather than a batch at a time: with batches the whole
// group waits for its slowest part, which on a busy store is most of the time.
async function inParallel<T>(items: T[], workers: number, work: (item: T) => Promise<void>) {
  const queue = [...items];
  let failed = false;

  await Promise.all(
    Array.from({ length: Math.min(workers, queue.length) }, async () => {
      for (let item = queue.shift(); item !== undefined; item = queue.shift()) {
        // One part that has given up ends the upload, so the others stop
        // rather than carry on sending for a file that will not be completed.
        if (failed) return;

        try {
          await work(item);
        } catch (e) {
          failed = true;

          throw e;
        }
      }
    }),
  );
}

function delay(ms: number, signal?: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(resolve, ms);

    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(new DOMException('Aborted', 'AbortError'));
      },
      { once: true },
    );
  });
}

function unquote(etag: string) {
  return etag.replaceAll('"', '');
}

function hexToBinary(hex: string) {
  return String.fromCharCode(...(hex.match(/../g) ?? []).map((pair) => parseInt(pair, 16)));
}

function isAborted(e: unknown) {
  return e instanceof DOMException && e.name === 'AbortError';
}

function isNotFound(e: unknown) {
  return (e as { status?: number } | undefined)?.status === 404;
}
