import Component from '@glimmer/component';
import { action } from '@ember/object';
import { LinkTo } from '@ember/routing';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { array, hash, uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';

import type Controller from 'repository/controllers/admin/users/index';
import type CurrentUserService from 'repository/services/current-user';
import type { components } from 'schema/openapi';

type Model = {
  users: components['schemas']['AdminUserSummary'][];
};

class UsersIndex extends Component<{ Args: { model: Model; controller: Controller } }> {
  @service declare currentUser: CurrentUserService;

  @action
  search(e: Event) {
    e.preventDefault();

    const form = e.target as HTMLFormElement;
    const value = new FormData(form).get('query');

    this.args.controller.query = typeof value === 'string' ? value : '';
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

        <button type="button" class="btn btn-sm btn-outline-dark" {{on "click" this.currentUser.stopProxy}}>
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

    <table class="table table-hover border">
      <thead class="table-light">
        <tr>
          <th>Username</th>
          <th>Name</th>
          <th>Email</th>
          <th>Organization</th>
          <th>Account type</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.users as |user|}}
          <tr class="position-relative">
            <td>
              <LinkTo
                @route="admin.users.user"
                @model={{user.uid}}
                class="stretched-link text-decoration-none text-reset"
              >
                {{user.uid}}
              </LinkTo>
            </td>
            <td>{{user.full_name}}</td>
            <td>{{user.email}}</td>
            <td>{{user.organization}}</td>
            <td>{{user.account_type_number}}</td>
          </tr>
        {{else}}
          <tr>
            <td colspan="5" class="text-center text-body-secondary py-4">No users found.</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>
}

export default UsersIndex;
