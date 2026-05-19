import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { array, hash } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';

import type CurrentUserService from 'repository/services/current-user';
import type { components } from 'schema/openapi';

type Model = components['schemas']['AdminUserDetail'];

class AdminUserDetailPage extends Component<{ Args: { model: Model } }> {
  @service declare currentUser: CurrentUserService;

  get isActiveProxy() {
    return this.currentUser.isProxyLoggedInAs(this.args.model.uid);
  }

  <template>
    {{pageTitle @model.uid}}

    <Breadcrumb
      @items={{array
        (hash label="Home" route="index")
        (hash label="Administration" route="admin")
        (hash label="Users" route="admin.users")
        (hash label=@model.uid)
      }}
    />

    <h1 class="display-6 mb-4">{{@model.uid}}</h1>

    <dl class="row">
      <dt class="col-sm-3">Name</dt>
      <dd class="col-sm-9">{{@model.full_name}}</dd>

      <dt class="col-sm-3">Email</dt>
      <dd class="col-sm-9">{{@model.email}}</dd>

      <dt class="col-sm-3">Organization</dt>
      <dd class="col-sm-9">{{@model.organization}}</dd>

      <dt class="col-sm-3">Account type</dt>
      <dd class="col-sm-9">{{@model.account_type_number}}</dd>

      <dt class="col-sm-3">Admin</dt>
      <dd class="col-sm-9">
        {{#if @model.admin}}
          <span class="badge text-bg-success">Yes</span>
        {{else}}
          <span class="badge text-bg-secondary">No</span>
        {{/if}}
      </dd>
    </dl>

    <h2 class="h5 mt-4">Activity</h2>

    <div class="row g-3 mb-4">
      <div class="col-md-6">
        <LinkTo @route="admin.requests" @query={{hash user=@model.uid}} class="card text-decoration-none h-100">
          <div class="card-body">
            <h3 class="card-title h6">Submission requests</h3>
            <p class="card-text text-body-secondary mb-0">View this user's submission requests.</p>
          </div>
        </LinkTo>
      </div>

      <div class="col-md-6">
        <LinkTo @route="admin.submissions" @query={{hash user=@model.uid}} class="card text-decoration-none h-100">
          <div class="card-body">
            <h3 class="card-title h6">Submissions</h3>
            <p class="card-text text-body-secondary mb-0">View this user's applied submissions.</p>
          </div>
        </LinkTo>
      </div>
    </div>

    <h2 class="h5 mt-4">Proxy login</h2>

    {{#if this.isActiveProxy}}
      <div class="alert alert-warning d-flex align-items-center justify-content-between" role="alert">
        <div>
          Currently acting as
          <strong>{{@model.uid}}</strong>.
        </div>

        <button type="button" class="btn btn-sm btn-outline-dark" {{on "click" this.currentUser.stopProxy}}>
          Deactivate
        </button>
      </div>
    {{else}}
      <button type="button" class="btn btn-outline-primary" {{on "click" (fn this.currentUser.startProxy @model.uid)}}>
        Proxy login as
        {{@model.uid}}
      </button>
    {{/if}}
  </template>
}

export default AdminUserDetailPage;
