import Component from '@glimmer/component';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { array, hash, uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';
import { eq } from 'ember-truth-helpers';

import Breadcrumb from 'repository/components/breadcrumb';

import type Controller from 'repository/controllers/admin/users';
import type CurrentUserService from 'repository/services/current-user';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type Model = {
  users: components['schemas']['AdminUserSummary'][];
};

class UsersIndex extends Component<{ Args: { model: Model; controller: Controller } }> {
  @service declare currentUser: CurrentUserService;
  @service declare toast: ToastService;

  @action
  search(e: Event) {
    e.preventDefault();

    const form = e.target as HTMLFormElement;
    const value = new FormData(form).get('query');

    this.args.controller.query = typeof value === 'string' ? value : '';
  }

  @action
  proxyLogin(uid: string) {
    this.currentUser.proxyUid = uid;

    this.toast.show(`Proxy login as ${uid}.`, 'success');
  }

  @action
  exitProxy() {
    this.currentUser.proxyUid = undefined;

    this.toast.show('Proxy login deactivated.', 'success');
  }

  <template>
    {{pageTitle "Users"}}

    <Breadcrumb
      @items={{array
        (hash label="Home" route="index")
        (hash label="Administration" route="admin")
        (hash label="Users")
      }}
    />

    <h1 class="display-6 mb-4">Users</h1>

    {{#if this.currentUser.isProxyLoggedIn}}
      <div class="alert alert-warning d-flex align-items-center justify-content-between" role="alert">
        <div>
          Currently acting as
          <strong>{{this.currentUser.proxyUid}}</strong>.
        </div>

        <button type="button" class="btn btn-sm btn-outline-dark" {{on "click" this.exitProxy}}>
          Deactivate
        </button>
      </div>
    {{/if}}

    <form class="mb-3" {{on "submit" this.search}}>
      {{#let (uniqueId) as |id|}}
        <label for={{id}} class="visually-hidden">Search</label>

        <div class="input-group">
          <input
            type="search"
            name="query"
            value={{@controller.query}}
            id={{id}}
            class="form-control"
            placeholder="Search by username, email, or name"
          />

          <button type="submit" class="btn btn-primary">Search</button>
        </div>
      {{/let}}
    </form>

    <p class="text-body-secondary small">
      Up to 100 users are shown. Refine your search if you don't see the user you're looking for.
    </p>

    <table class="table border">
      <thead class="table-light">
        <tr>
          <th>Username</th>
          <th>Name</th>
          <th>Email</th>
          <th>Organization</th>
          <th>Account type</th>
          <th class="text-end">Actions</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.users as |user|}}
          <tr>
            <td>{{user.uid}}</td>
            <td>{{user.full_name}}</td>
            <td>{{user.email}}</td>
            <td>{{user.organization}}</td>
            <td>{{user.account_type_number}}</td>
            <td class="text-end">
              {{#if (eq user.uid this.currentUser.proxyUid)}}
                <span class="badge text-bg-secondary">Active</span>
              {{else}}
                <button
                  type="button"
                  class="btn btn-sm btn-outline-primary"
                  {{on "click" (fn this.proxyLogin user.uid)}}
                >
                  Proxy login
                </button>
              {{/if}}
            </td>
          </tr>
        {{else}}
          <tr>
            <td colspan="6" class="text-center text-body-secondary py-4">No users found.</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>
}

export default UsersIndex;
