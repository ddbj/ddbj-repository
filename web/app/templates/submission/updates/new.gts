import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import { DirectUpload } from '@rails/activestorage';

import ENV from 'repository/config/environment';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { Blob } from '@rails/activestorage';
import type { components, paths } from 'schema/openapi';

type CreateUpdateResponse =
  paths['/{db}/submissions/{id}/updates']['post']['responses']['202']['content']['application/json'];

interface Signature {
  Args: {
    model: { db: string } & components['schemas']['Submission'];
  };
}

export default class extends Component<Signature> {
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

    const { db, id: submission_id } = this.args.model;
    const upload = new DirectUpload(this.file, ENV.directUploadURL);

    const blob = await new Promise<Blob>((resolve, reject) => {
      upload.create((err, blob) => (err ? reject(err) : resolve(blob!)));
    });

    const { content } = await this.requestManager.request<CreateUpdateResponse>({
      url: `/${db}/submissions/${submission_id}/updates`,
      method: 'POST',
      data: { submission_update: { ddbj_record: blob.signed_id } },
    });

    this.router.transitionTo('update', db, content.id);
  }

  <template>
    <h1 class="display-6 mb-4">Update Submission</h1>

    <form {{on "submit" this.submit}}>
      <div class="mb-3">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="form-label">DDBJ Record</label>
          <input id={{id}} type="file" class="form-control" accept=".json" {{on "change" this.selectFile}} />
        {{/let}}
      </div>

      <button type="submit" class="btn btn-primary">Validate</button>
    </form>
  </template>
}
