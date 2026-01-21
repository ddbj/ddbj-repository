import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import { DirectUpload } from '@rails/activestorage';

import ENV from 'repository/config/environment';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type { Blob } from '@rails/activestorage';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    model: components['schemas']['Submission'];
  };
}

export default class extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: RouterService;

  file?: File;

  @action
  selectFile(e: Event) {
    this.file = (e.target! as HTMLInputElement).files?.[0];
  }

  @action
  submit(e: Event) {
    e.preventDefault();

    if (!this.file) {
      return;
    }

    const upload = new DirectUpload(this.file, ENV.directUploadURL);

    upload.create((err: Error | null, blob?: Blob) => {
      if (err) {
        alert(`Upload failed: ${err.message}`);
        return;
      }

      const { model } = this.args;

      void this.request
        .fetchWithModal(`/submissions/${model.id}/updates`, {
          method: 'POST',

          headers: {
            'Content-Type': 'application/json',
          },

          body: JSON.stringify({
            submission_update: {
              ddbj_record: blob!.signed_id,
            },
          }),
        })
        .then((res) => res.json())
        .then(({ id }: { id: number }) => {
          this.router.transitionTo('update', id);
        });
    });
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
