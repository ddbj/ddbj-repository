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

    <h1 class="mb-6 text-3xl font-light">Account</h1>

    <div class="rounded-lg border border-gray-200 bg-white p-6 shadow-sm">
      <div class="mb-4 grid items-center gap-2 sm:grid-cols-6">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="text-sm font-medium text-gray-700 sm:col-span-1">Username</label>

          <input
            type="text"
            value={{this.currentUser.user.uid}}
            readonly
            id={{id}}
            class="bg-transparent text-gray-900 sm:col-span-5"
          />
        {{/let}}
      </div>

      <div class="grid items-center gap-2 sm:grid-cols-6">
        {{#let (uniqueId) as |id|}}
          <label for={{id}} class="text-sm font-medium text-gray-700 sm:col-span-1">API key</label>

          <div class="flex gap-2 sm:col-span-5">
            <input
              type="text"
              value={{this.currentUser.user.apiKey}}
              readonly
              id={{id}}
              class="flex-1 rounded-md border border-gray-300 bg-white px-3 py-2 font-mono text-sm text-gray-900 focus:border-blue-500 focus:ring-2 focus:ring-blue-500 focus:outline-none"
            />

            <button
              type="button"
              class="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
              {{on "click" this.copyApiKey}}
            >
              Copy
            </button>

            <button
              type="button"
              class="rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50"
              {{on "click" this.regenerateApiKey}}
            >
              Regenerate
            </button>
          </div>
        {{/let}}
      </div>
    </div>
  </template>
}
