import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import SubmissionSteps from 'repository/components/submission-steps';
import dbLabel from 'repository/helpers/db-label';
import uploadFile from 'repository/utils/multipart-upload';
import { errorMessage } from 'repository/utils/error-message';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { Progress } from 'repository/utils/multipart-upload';
import type { paths } from 'schema/openapi';

type CreateRequestResponse = paths['/submission_requests']['post']['responses']['202']['content']['application/json'];

interface Signature {
  Args: {
    model: { db: string };
  };
}

export default class extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @tracked file?: File;
  @tracked progress?: Progress;
  @tracked verifying = false;
  @tracked error?: string;

  // The record goes up in parts (`/api/uploads`). A DDBJ Record is a whole
  // genome for some submitters — the file a browser is asked to send here is
  // measured in GB, so it is sent in parts, it reports how far it has got, and
  // choosing the same file again after a failure carries on from where it
  // stopped rather than starting over.
  @action
  selectFile(e: Event) {
    this.file = (e.target! as HTMLInputElement).files?.[0];
    this.error = undefined;
  }

  get uploading() {
    return this.progress !== undefined || this.verifying;
  }

  get percent() {
    if (!this.progress?.total) return 0;

    return Math.floor((this.progress.sent / this.progress.total) * 100);
  }

  @action
  async submit(e: Event) {
    e.preventDefault();

    if (!this.file || this.uploading) return;

    const { db } = this.args.model;

    this.error = undefined;
    this.progress = { sent: 0, total: this.file.size };

    try {
      const signedBlobId = await uploadFile(this.file, {
        requestManager: this.requestManager,
        onProgress: (progress) => (this.progress = progress),
      });

      // Sent, and now being read through for its checksum. Minutes, for a
      // large file, and the reader is told so rather than left at 100%.
      this.verifying = true;

      const { content } = await this.requestManager.request<CreateRequestResponse>({
        url: '/submission_requests',
        method: 'POST',
        data: { submission_request: { db, ddbj_record: signedBlobId } },
      });

      this.router.transitionTo('request', content.id);
    } catch (e) {
      this.error = errorMessage(e) ?? (e as Error).message ?? 'The upload did not finish. Try again.';
    } finally {
      this.progress = undefined;
      this.verifying = false;
    }
  }

  <template>
    <Breadcrumb
      @items={{array
        (hash label="Home" route="index")
        (hash label="New Submission" route="new")
        (hash label=(dbLabel @model.db))
      }}
    />

    <h1 class="display-6 mb-3">New Submission ({{dbLabel @model.db}})</h1>

    <SubmissionSteps @current={{2}} />

    <form {{on "submit" this.submit}}>
      <div class="mb-3">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="form-label">DDBJ Record</label>
          <input
            id={{id}}
            type="file"
            class="form-control"
            accept=".json"
            disabled={{this.uploading}}
            {{on "change" this.selectFile}}
          />
        {{/let}}
      </div>

      {{#if this.uploading}}
        <div class="mb-3" data-test-upload-progress>
          {{! The native element rather than Bootstrap's two divs: the
          width of those is an inline style, which is the one way of
          drawing a bar this codebase does not allow. }}
          <progress class="w-100" aria-label="Upload progress" value={{this.progress.sent}} max={{this.progress.total}}>
            {{this.percent}}%
          </progress>

          <p class="small text-body-secondary mt-1 mb-0">
            {{#if this.verifying}}
              Checking the file we received. This can take a few minutes for a large file.
            {{else}}
              Uploading…
              {{this.percent}}%. You can pick the same file again to carry on if this is interrupted.
            {{/if}}
          </p>
        </div>
      {{/if}}

      {{#if this.error}}
        <div class="alert alert-danger" role="alert" data-test-upload-error>{{this.error}}</div>
      {{/if}}

      {{! "Check", not "Validate": what it does is tell you whether
      this would be accepted, and it can be done as often as you like.
      Nothing leaves for DDBJ until Send, on the step after this one. }}
      <button type="submit" class="btn btn-primary" disabled={{this.uploading}}>Check my data</button>

      <p class="small text-body-secondary mt-2 mb-0">Nothing is sent to DDBJ yet.</p>
    </form>
  </template>
}
