import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import type CurrentUserService from 'repository/services/current-user';
import type RequestService from 'repository/services/request';
import type ToastService from 'repository/services/toast';

export default class Account extends Component {
  @service declare currentUser: CurrentUserService;
  @service declare request: RequestService;
  @service declare toast: ToastService;

  @action
  async copyApiKey() {
    await navigator.clipboard.writeText(this.currentUser.user!.apiKey);

    this.toast.show('Copied to clipboard.', 'success');
  }

  @action
  async regenerateApiKey() {
    const res = await this.request.fetchWithModal('/api_key/regenerate', {
      method: 'POST',
    });

    const { api_key } = (await res.json()) as { api_key: string };

    this.currentUser.user!.apiKey = api_key;
  }

  <template>
    {{pageTitle "Account"}}

    <div class="card">
      <div class="card-body">
        <div class="row mb-3">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="col-sm-2 col-form-label">Username</label>

            <div class="col-sm-10">
              <input
                type="text"
                value={{this.currentUser.user.uid}}
                readonly
                id={{id}}
                class="form-control-plaintext"
              />
            </div>
          {{/let}}
        </div>

        <div class="row">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="col-sm-2 col-form-label">API key</label>

            <div class="col-sm-10">
              <div class="input-group">
                <input type="text" value={{this.currentUser.user.apiKey}} readonly id={{id}} class="form-control" />

                <button type="button" class="btn btn-outline-secondary" {{on "click" this.copyApiKey}}>
                  Copy
                </button>

                <button type="button" class="btn btn-outline-secondary" {{on "click" this.regenerateApiKey}}>
                  Regenerate
                </button>
              </div>
            </div>
          {{/let}}
        </div>
      </div>
    </div>
  </template>
}
