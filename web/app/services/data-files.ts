import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import uploadFile from 'repository/utils/multipart-upload';
import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type { Progress } from 'repository/utils/multipart-upload';
import type { components } from 'schema/openapi';

export type UploadedFile = components['schemas']['File'];

const CARRY_ON = 'Choose the file again to carry on from where it stopped.';

// One file chosen to go up: waiting its turn, going, or stopped with a
// reason.
export class Upload {
  @tracked progress?: Progress;
  @tracked error?: string;

  constructor(readonly file: File) {}

  get percent() {
    if (!this.progress?.total) return 0;

    return Math.floor((this.progress.sent / this.progress.total) * 100);
  }

  get verifying() {
    return this.progress?.state === 'verifying';
  }

  // What utils/multipart-upload recognises a file by, short of reading it.
  matches(file: File) {
    return file.name === this.file.name && file.size === this.file.size && file.lastModified === this.file.lastModified;
  }
}

// The account's data files: the ones waiting for a record to name them
// (`/unassigned_files`), and the ones going up to join them.
//
// The account's, not a page's, so uploads outlive the page they were started
// on. Reads run to tens of GB and take hours; a press of "Check my data", a
// breadcrumb, anything that left the page used to stop them without a word.
// Closing the tab still stops them — the browser is asked to say so — and
// choosing the same file again carries on from what the store already holds.
//
// One file at a time. Each goes up in parts several at once already, and a
// browser holding the parts of four files of tens of GB together is a browser
// that stops.
//
// An account's, so it is emptied when the account changes (`reset`, from
// CurrentUserService): a file chosen for one submitter would otherwise go on
// up into the next account signed in, or a curator's own once they stop
// acting for somebody.
export default class DataFilesService extends Service {
  @service declare requestManager: RequestManager;

  @tracked files: UploadedFile[] = [];
  @tracked page = 1;
  @tracked pages = 1;
  @tracked loading = false;
  @tracked loadError?: string;

  @tracked removing?: number;
  @tracked removeError?: string;

  @tracked uploads: Upload[] = [];

  // The last upload to finish, said once rather than as every tick of it.
  @tracked finished?: string;

  #abort = new AbortController();
  #draining = false;

  // Which `load` is the latest: one that answers after a later one began —
  // paging while a finished upload reloads the first page — is not shown.
  #loads = 0;

  #warn = (e: BeforeUnloadEvent) => {
    if (!this.pending) return;

    e.preventDefault();

    // What older Chromium and Safari still go by.
    e.returnValue = '';
  };

  constructor(owner: object) {
    // @ts-expect-error -- Service owner typing
    super(owner);

    window.addEventListener('beforeunload', this.#warn);
  }

  willDestroy() {
    super.willDestroy();

    window.removeEventListener('beforeunload', this.#warn);
    this.#abort.abort();
  }

  reset() {
    this.#abort.abort();
    this.#abort = new AbortController();
    this.#loads++;

    this.uploads = [];
    this.files = [];
    this.page = this.pages = 1;
    this.loading = false;
    this.loadError = this.removeError = this.finished = undefined;
  }

  // Going, or waiting to go: what a record checked now would not yet find.
  get pending() {
    return this.uploads.some((upload) => !upload.error);
  }

  async load(page: number) {
    const load = ++this.#loads;

    this.loading = true;
    this.loadError = this.removeError = undefined;

    try {
      const { content, response } = await this.requestManager.request<UploadedFile[]>({
        url: '/unassigned_files',
        options: { params: { page }, reportErrors: false },
      });

      if (load !== this.#loads) return;

      this.files = content;
      this.page = page;
      this.pages = Number(response?.headers?.get('Total-Pages')) || 1;
    } catch (e) {
      if (load !== this.#loads) return;

      this.loadError = errorMessage(e) || 'Your files could not be listed. Reload the page to try again.';
    } finally {
      if (load === this.#loads) this.loading = false;
    }
  }

  // A file already going or waiting is not queued twice: it would be sent in
  // full a second time once the first had finished. One that stopped is
  // replaced, so its reason gives way to the new attempt.
  add(chosen: File[]) {
    const fresh = chosen.filter((file) => !this.uploads.some((upload) => !upload.error && upload.matches(file)));
    const kept = this.uploads.filter((upload) => !(upload.error && fresh.some((file) => upload.matches(file))));

    this.uploads = [...kept, ...fresh.map((file) => new Upload(file))];

    void this.drain();
  }

  dismiss(upload: Upload) {
    this.uploads = this.uploads.filter((u) => u !== upload);
  }

  async drain() {
    if (this.#draining) return;

    this.#draining = true;

    try {
      let upload: Upload | undefined;

      while ((upload = this.uploads.find((upload) => !upload.error))) {
        await this.send(upload);
      }
    } catch {
      // Stopped by `reset` or with the application: what it was sending is
      // gone with the queue, and there is nothing to say it on.
    } finally {
      this.#draining = false;
    }
  }

  async send(upload: Upload) {
    const { signal } = this.#abort;

    upload.progress = { sent: 0, total: upload.file.size, state: 'uploading' };

    try {
      await uploadFile(upload.file, {
        requestManager: this.requestManager,
        signal,
        onProgress: (progress) => (upload.progress = progress),
      });
    } catch (e) {
      // Stopped by this queue (`reset`, or with the application) ends the
      // draining; anything else, however it was raised, is this upload's,
      // and said on it — not a queue left waiting on it for good.
      if (signal.aborted) throw e;

      upload.error = `${errorMessage(e) || (e as Error).message || 'The upload did not finish.'} ${CARRY_ON}`;
      upload.progress = undefined;

      return;
    }

    this.dismiss(upload);
    this.finished = upload.file.name;

    // Newest first, so it is on the first page — which is reloaded only for
    // somebody on it, not pulled out from under somebody reading page 3.
    if (this.page === 1) await this.load(1);
  }

  async remove(file: UploadedFile) {
    this.removing = file.id;
    this.removeError = undefined;

    try {
      await this.requestManager.request({
        url: `/unassigned_files/${file.id}`,
        method: 'DELETE',
        options: { reportErrors: false },
      });
    } catch (e) {
      this.removeError = errorMessage(e) || `${file.filename} could not be taken out.`;

      return;
    } finally {
      this.removing = undefined;
    }

    await this.load(this.files.length === 1 && this.page > 1 ? this.page - 1 : this.page);
  }
}
