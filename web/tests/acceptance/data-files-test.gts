import { module, test } from 'qunit';
import { visit, click, triggerEvent, waitFor, waitUntil } from '@ember/test-helpers';
import { HttpResponse, http as mswHttp } from 'msw';

import ENV from 'repository/config/environment';
import { setupApplicationTest } from 'repository/tests/helpers';
import { setupAuthentication } from 'repository/tests/helpers/setup-auth';

import { http } from '../msw/http';
import { worker } from '../msw/worker';

import type { components } from 'schema/openapi';

type UploadedFile = components['schemas']['File'];

function uploaded(id: number, filename: string): UploadedFile {
  return {
    id,
    filename,
    content_type: 'application/octet-stream',
    byte_size: 2 * 1024 ** 3,
    md5: 'd41d8cd98f00b204e9800998ecf8427e',
    signed_blob_id: `signed-${id}`,
    created_at: '2026-10-01T00:00:00.000Z',
    expires_at: '2026-10-08T00:00:00.000Z',
  };
}

// The reads a DRA record names go up before it does, and are the account's
// rather than one request's: the page lists what is waiting, and adds to it.
module('Acceptance | data files', function (hooks) {
  setupApplicationTest(hooks);
  setupAuthentication(hooks);

  hooks.beforeEach(function () {
    worker.use(
      http.get('/me', ({ response }) =>
        response(200).json({
          uid: 'test-user',
          api_key: 'test-api-key',
          admin: false,
          submittable_dbs: ['st26', 'dra'],
        }),
      ),
    );
  });

  test('a DRA submission starts from the files waiting for it, and adds to them', async function (assert) {
    let files = [uploaded(1, 'run1_R1.fastq.gz')];

    worker.use(http.get('/unassigned_files', ({ response }) => response(200).json(files)));

    await visit('/dra/requests/new');
    await waitFor('[data-test-data-file="run1_R1.fastq.gz"]', { timeout: 5000 });

    assert.dom('[data-test-data-file="run1_R1.fastq.gz"]').includesText('2.0 GB');

    // Once verified, the upload is among the files, newest first.
    files = [uploaded(2, 'run1_R2.fastq.gz'), ...files];

    await triggerEvent('[data-test-data-files] input[type="file"]', 'change', {
      files: [new File(['@r\nACGT\n+\nIIII\n'], 'run1_R2.fastq.gz')],
    });

    await waitFor('[data-test-data-file="run1_R2.fastq.gz"]', { timeout: 5000 });

    assert.dom('[data-test-upload]').doesNotExist('nothing left going up');
    assert.dom('[data-test-data-file]').exists({ count: 2 });
  });

  test('a file can be taken out, and a refusal says why', async function (assert) {
    let files = [uploaded(1, 'wrong.fastq'), uploaded(2, 'right.fastq')];
    let refuse = false;

    worker.use(
      http.get('/unassigned_files', ({ response }) => response(200).json(files)),
      http.delete('/unassigned_files/{id}', ({ params, response }) => {
        if (refuse) {
          return response(403).json({ error: 'A curator acting for you cannot discard your files.' });
        }

        files = files.filter((file) => file.id !== Number(params.id));

        return response(204).empty();
      }),
    );

    await visit('/dra/requests/new');
    await waitFor('[data-test-data-file="wrong.fastq"]', { timeout: 5000 });
    await click('[aria-label="Remove wrong.fastq"]');

    assert.dom('[data-test-data-file="wrong.fastq"]').doesNotExist();
    assert.dom('[data-test-data-file="right.fastq"]').exists();

    refuse = true;

    await click('[aria-label="Remove right.fastq"]');

    assert.dom('[data-test-data-files-error]').includesText('cannot discard');
    assert.dom('[data-test-data-file="right.fastq"]').exists();
  });

  // Only DRA's records name files of their own.
  test('other databases are not offered data files', async function (assert) {
    await visit('/st26/requests/new');

    assert.dom('[data-test-data-files]').doesNotExist();
  });
  // Checked now, the record would be refused for each file still going up.
  test('the record cannot be checked while its files are still going up', async function (assert) {
    let release!: () => void;
    const held = new Promise<void>((resolve) => (release = resolve));

    worker.use(
      http.get('/unassigned_files', ({ response }) => response(200).json([])),
      http.post('/uploads', async ({ response }) => {
        await held;

        return response(201).json({
          token: 't',
          state: 'uploading',
          part_size: 16 * 1024 * 1024,
          part_count: 1,
          parts: [],
          signed_blob_id: null,
        });
      }),
    );

    await visit('/dra/requests/new');

    void triggerEvent('[data-test-data-files] input[type="file"]', 'change', {
      files: [new File(['@r\nACGT\n+\nIIII\n'], 'run1.fastq')],
    });

    await waitFor('[data-test-upload="run1.fastq"]', { timeout: 5000 });

    assert.dom('button[type="submit"]').isDisabled();
    assert.dom('[data-test-waiting-for-data-files]').exists();

    release();
    await waitUntil(() => !document.querySelector('[data-test-upload]'), { timeout: 5000 });

    assert.dom('button[type="submit"]').isNotDisabled();
  });

  test('an upload that stops says so, and choosing the file again replaces the reason', async function (assert) {
    let refuse = true;

    worker.use(
      http.get('/unassigned_files', ({ response }) => response(200).json([])),
      http.post('/uploads', ({ response }) =>
        refuse
          ? response(422).json({ error: 'The upload was refused.' })
          : response(201).json({
              token: 't',
              state: 'uploading',
              part_size: 16 * 1024 * 1024,
              part_count: 1,
              parts: [],
              signed_blob_id: null,
            }),
      ),
    );

    await visit('/dra/requests/new');

    const file = new File(['@r\nACGT\n+\nIIII\n'], 'run1.fastq');

    await triggerEvent('[data-test-data-files] input[type="file"]', 'change', { files: [file] });
    await waitFor('[data-test-upload="run1.fastq"] [role="alert"]', { timeout: 5000 });

    assert.dom('[data-test-upload="run1.fastq"] [role="alert"]').includesText('Choose the file again to carry on');
    assert.dom('button[type="submit"]').isNotDisabled('a stopped upload is not one being waited for');

    refuse = false;

    await triggerEvent('[data-test-data-files] input[type="file"]', 'change', { files: [file] });
    await waitUntil(() => !document.querySelector('[data-test-upload]'), { timeout: 5000 });

    assert.dom('[data-test-upload]').doesNotExist('gone up, and the reason with it');
  });

  // Said as a failure, not as an empty list: the files are there.
  test('a list that could not be read says so', async function (assert) {
    worker.use(
      mswHttp.get(`${ENV.apiURL}/unassigned_files`, () => HttpResponse.json({ error: 'Busy.' }, { status: 503 })),
    );

    await visit('/dra/requests/new');
    await waitFor('[data-test-data-files-load-error]', { timeout: 5000 });

    assert.dom('[data-test-no-data-files]').doesNotExist();
  });
});
