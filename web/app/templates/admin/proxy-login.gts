import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import type CurrentUserService from 'repository/services/current-user';

export default class extends Component {
  @service declare currentUser: CurrentUserService;

  @tracked uid?: string;

  @action
  setUid(e: Event) {
    this.uid = (e.target as HTMLInputElement).value;
  }

  @action
  submit(e: Event) {
    e.preventDefault();

    this.currentUser.proxyUid = this.uid;
  }

  @action
  exit() {
    this.currentUser.proxyUid = this.uid = undefined;
  }

  <template>
    {{pageTitle "Proxy Login"}}

    <div class="card">
      <div class="card-body">
        <form {{on "submit" this.submit}}>
          <div class="mb-3">
            {{#let (uniqueId) as |id|}}
              <label for={{id}} class="form-label">
                D-way User ID
              </label>

              <input
                type="text"
                value={{this.uid}}
                readonly={{this.currentUser.isProxyLoggedIn}}
                id={{id}}
                class={{if this.currentUser.isProxyLoggedIn "form-control-plaintext" "form-control"}}
                {{on "change" this.setUid}}
              />
            {{/let}}
          </div>

          {{#if this.currentUser.isProxyLoggedIn}}
            <button type="button" class="btn btn-danger" {{on "click" this.exit}}>Deactivate</button>
          {{else}}
            <button type="submit" class="btn btn-primary">Switch User</button>
          {{/if}}
        </form>
      </div>
    </div>
  </template>
}
