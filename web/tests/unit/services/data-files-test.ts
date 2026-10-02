import { module, test } from 'qunit';
import { setupTest } from 'repository/tests/helpers';

import type DataFilesService from 'repository/services/data-files';

module('Unit | Service | data-files', function (hooks) {
  setupTest(hooks);

  // Chosen again while it is still going or waiting — the bar looked stuck —
  // it is not queued a second time, which would send it in full again once
  // the first had finished.
  test('a file already going up is not queued twice', function (assert) {
    const service = this.owner.lookup('service:data-files') as DataFilesService;

    service.drain = () => Promise.resolve();

    const file = new File(['ACGT'], 'run1.fastq', { lastModified: 1 });

    service.add([file]);
    service.add([new File(['ACGT'], 'run1.fastq', { lastModified: 1 })]);

    assert.strictEqual(service.uploads.length, 1);

    service.uploads[0]!.error = 'Stopped.';
    service.add([file]);

    assert.strictEqual(service.uploads.length, 1, 'a stopped one is replaced');
    assert.strictEqual(service.uploads[0]!.error, undefined);

    service.add([new File(['ACGT'], 'run1.fastq', { lastModified: 2 })]);

    assert.strictEqual(service.uploads.length, 2, 'a different file of the same name is another upload');
  });

  // A file chosen for one account does not go up into the next one signed
  // in — or into a curator's own once they stop acting for somebody.
  test('a change of account empties the queue', function (assert) {
    const service = this.owner.lookup('service:data-files') as DataFilesService;
    const currentUser = this.owner.lookup('service:current-user') as { clear(): void; stopProxy(): void };

    service.drain = () => Promise.resolve();

    service.add([new File(['ACGT'], 'run1.fastq')]);
    currentUser.clear();

    assert.strictEqual(service.uploads.length, 0, 'signed out');

    service.add([new File(['ACGT'], 'run1.fastq')]);
    currentUser.stopProxy();

    assert.strictEqual(service.uploads.length, 0, 'no longer acting for them');
  });
});
