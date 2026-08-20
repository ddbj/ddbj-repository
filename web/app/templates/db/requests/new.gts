import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import { DirectUpload } from '@rails/activestorage';

import ENV from 'repository/config/environment';

import Breadcrumb from 'repository/components/breadcrumb';
import SubmissionSteps from 'repository/components/submission-steps';
import dbLabel from 'repository/helpers/db-label';

import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { Blob } from '@rails/activestorage';
import type { paths } from 'schema/openapi';

type CreateRequestResponse = paths['/submission_requests']['post']['responses']['202']['content']['application/json'];

interface Signature {
  Args: {
    model: { db: string };
  };
}

export default class extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  file?: File;

  @action
  selectFile(e: Event) {
    this.file = (e.target! as HTMLInputElement).files?.[0];
  }

  @action
  async submit(e: Event) {
    e.preventDefault();

    if (!this.file) return;

    const { db } = this.args.model;
    // The endpoint authenticates now (it mints a blob row and a presigned
    // PUT, which is not something to leave open), and @rails/activestorage
    // sends only its own headers unless it is given more.
    const upload = new DirectUpload(this.file, ENV.directUploadURL, undefined, this.currentUser.authorizationHeader);

    const blob = await new Promise<Blob>((resolve, reject) => {
      upload.create((err, blob) => (err ? reject(err) : resolve(blob!)));
    });

    const { content } = await this.requestManager.request<CreateRequestResponse>({
      url: '/submission_requests',
      method: 'POST',
      data: { submission_request: { db, ddbj_record: blob.signed_id } },
    });

    this.router.transitionTo('request', content.id);
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
          <input id={{id}} type="file" class="form-control" accept=".json" {{on "change" this.selectFile}} />
        {{/let}}
      </div>

      {{! "Check", not "Validate": what it does is tell you whether
      this would be accepted, and it can be done as often as you like.
      Nothing leaves for DDBJ until Send, on the step after this one. }}
      <button type="submit" class="btn btn-primary">Check my data</button>

      <p class="small text-body-secondary mt-2 mb-0">Nothing is sent to DDBJ yet.</p>
    </form>
  </template>
}
