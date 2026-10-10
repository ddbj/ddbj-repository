import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import Pager from 'repository/components/pager';
import formatDatetime from 'repository/helpers/format-datetime';
import humanSize from 'repository/helpers/human-size';

import type CurrentUserService from 'repository/services/current-user';
import type DataFilesService from 'repository/services/data-files';
import type { Upload, UploadedFile } from 'repository/services/data-files';

// The files a DRA record's runs and analyses name, uploaded before the record
// is checked: the check looks for each among these, by name and by the MD5 the
// record states (DRA::RecordFiles). The account's list of what is waiting, and
// the way to add to it — the uploads themselves are the DataFilesService's, so
// they carry on when this page is left.
export default class DataFiles extends Component {
  @service declare currentUser: CurrentUserService;
  @service('data-files') declare dataFiles: DataFilesService;

  constructor(owner: unknown, args: object) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.dataFiles.load(1);
  }

  @action
  choose(e: Event) {
    const input = e.target as HTMLInputElement;

    this.dataFiles.add(Array.from(input.files ?? []));

    // Cleared, so choosing the same file again — to carry on an upload that
    // stopped — is a change the input reports.
    input.value = '';
  }

  @action
  go(page: number) {
    void this.dataFiles.load(page);
  }

  @action
  dismiss(upload: Upload) {
    this.dataFiles.dismiss(upload);
  }

  @action
  remove(file: UploadedFile) {
    void this.dataFiles.remove(file);
  }

  // Taking a file out is the account holder's; a curator acting for them can
  // upload, but is refused this.
  get removable() {
    return !this.currentUser.isProxyLoggedIn;
  }

  <template>
    <section class="mb-4" data-test-data-files>
      <h2 class="h5">Data files</h2>

      <p class="small text-body-secondary">
        Upload the files your runs and analyses name before you check the DDBJ Record: the check looks for each by its
        file name and the MD5 the record states for it. Files are kept for your account, not for one submission, and one
        that no submission uses is let go of about a week after it was uploaded.
      </p>

      <div class="mb-3">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="form-label">Add files</label>
          <input id={{id}} type="file" class="form-control" multiple {{on "change" this.choose}} />
        {{/let}}
      </div>

      {{#if this.dataFiles.uploads.length}}
        <ul class="list-unstyled mb-3" data-test-uploads>
          {{#each this.dataFiles.uploads as |upload|}}
            <li class="mb-2" data-test-upload={{upload.file.name}}>
              <div class="d-flex justify-content-between small">
                <span class="text-break">{{upload.file.name}}</span>
                <span class="text-body-secondary text-nowrap ms-2">{{humanSize upload.file.size}}</span>
              </div>

              {{#if upload.error}}
                <div class="alert alert-danger d-flex justify-content-between align-items-start py-2 mb-0" role="alert">
                  <span>{{upload.error}}</span>
                  <button
                    type="button"
                    class="btn-close"
                    aria-label="Dismiss {{upload.file.name}}"
                    {{on "click" (fn this.dismiss upload)}}
                  ></button>
                </div>
              {{else if upload.progress}}
                {{! The native element rather than Bootstrap's two divs: the
                width of those is an inline style, which is the one way of
                drawing a bar this codebase does not allow. The bar carries
                the value; the text under it is not a live region, which
                would read every tick aloud. }}
                <progress
                  class="w-100"
                  aria-label="Upload progress of {{upload.file.name}}"
                  value={{upload.progress.sent}}
                  max={{upload.progress.total}}
                >{{upload.percent}}%</progress>

                <p class="small text-body-secondary mb-0">
                  {{#if upload.verifying}}
                    Checking the file we received. This can take a few minutes for a large file.
                  {{else}}
                    Uploading…
                    {{upload.percent}}%. It carries on if you leave this page; closing the tab stops it.
                  {{/if}}
                </p>
              {{else}}
                <p class="small text-body-secondary mb-0">Waiting for the files before it.</p>
              {{/if}}
            </li>
          {{/each}}
        </ul>
      {{/if}}

      {{! One line, said when a file has gone up, rather than the bar's
      every tick. }}
      <p class="visually-hidden" role="status" data-test-data-files-finished>
        {{#if this.dataFiles.finished}}{{this.dataFiles.finished}} uploaded.{{/if}}
      </p>

      {{#if this.dataFiles.removeError}}
        <div class="alert alert-danger" role="alert" data-test-data-files-error>{{this.dataFiles.removeError}}</div>
      {{/if}}

      {{#if this.dataFiles.loadError}}
        <div class="alert alert-danger" role="alert" data-test-data-files-load-error>{{this.dataFiles.loadError}}</div>
      {{else if this.dataFiles.files.length}}
        <div class="table-responsive">
          <table class="table table-sm align-middle">
            <thead>
              <tr>
                <th scope="col">File</th>
                <th scope="col" class="text-end">Size</th>
                <th scope="col">MD5</th>
                <th scope="col">Kept until at least</th>
                {{#if this.removable}}
                  <th scope="col"><span class="visually-hidden">Actions</span></th>
                {{/if}}
              </tr>
            </thead>

            <tbody>
              {{#each this.dataFiles.files as |file|}}
                <tr data-test-data-file={{file.filename}}>
                  <td class="text-break">{{file.filename}}</td>
                  <td class="text-end text-nowrap">{{humanSize file.byte_size}}</td>
                  <td><code class="small">{{file.md5}}</code></td>
                  <td class="text-nowrap">{{formatDatetime file.expires_at}}</td>
                  {{#if this.removable}}
                    <td class="text-end">
                      <button
                        type="button"
                        class="btn btn-outline-secondary btn-sm"
                        aria-label="Remove {{file.filename}}"
                        disabled={{if this.dataFiles.loading true (if this.dataFiles.removing true)}}
                        {{on "click" (fn this.remove file)}}
                      >Remove</button>
                    </td>
                  {{/if}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>

        <Pager
          @page={{this.dataFiles.page}}
          @pages={{this.dataFiles.pages}}
          @busy={{this.dataFiles.loading}}
          @label="data files"
          @go={{this.go}}
        />
      {{else if this.dataFiles.loading}}
        <p class="small text-body-secondary" role="status">Loading your files…</p>
      {{else}}
        <p class="small text-body-secondary" data-test-no-data-files>No files are waiting. Add the ones your record
          names.</p>
      {{/if}}
    </section>
  </template>
}
