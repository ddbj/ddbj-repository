import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import { DirectUpload } from '@rails/activestorage';

import ENV from 'repository/config/environment';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';

export default class extends Component {
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

    if (!this.file) { return; }

    const upload = new DirectUpload(this.file, ENV.directUploadURL);

    upload.create(async (err: Error | null, blob: { signed_id: string }) => {
      if (err) {
        alert(`Upload failed: ${err.message}`);
        return;
      }

      const res = await this.request.fetchWithModal('/submission_requests', {
        method: 'POST',

        headers: {
          'Content-Type': 'application/json'
        },

        body: JSON.stringify({
          submission_request: {
            ddbj_record: blob.signed_id
          }
        })
      });

      const { id } = await res.json();

      this.router.transitionTo('request', id);
    });
  }

  <template>
    <h1>New Request</h1>

    <form {{on "submit" this.submit}}>
      <input type="hidden" name="db" value="Trad" />

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
