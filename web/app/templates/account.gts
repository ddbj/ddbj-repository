import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { array, hash, uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';

import type { RequestManager } from '@warp-drive/core';
import type CurrentUserService from 'repository/services/current-user';
import type ToastService from 'repository/services/toast';
import type { paths } from 'schema/openapi';

type RegenerateApiKey = paths['/api_key/regenerate']['post']['responses']['200']['content']['application/json'];

export default class Account extends Component {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @action
  async copyApiKey() {
    await navigator.clipboard.writeText(this.currentUser.user!.apiKey);

    this.toast.show('Copied to clipboard.', 'success');
  }

  @action
  async regenerateApiKey() {
    const { content } = await this.requestManager.request<RegenerateApiKey>({
      url: '/api_key/regenerate',
      method: 'POST',
    });

    this.currentUser.user!.apiKey = content.api_key;
  }

  <template>
    {{pageTitle "Account"}}

    <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="Account")}} />

    <h1 class="display-6 mb-4">Account</h1>

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
