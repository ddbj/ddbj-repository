import Component from '@glimmer/component';
import { action } from '@ember/object';
import { LinkTo } from '@ember/routing';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { Textarea } from '@ember/component';
import { tracked } from '@glimmer/tracking';
import { array, hash, uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';

import type { RequestManager } from '@warp-drive/core';
import type Owner from '@ember/owner';
import type CurrentUserService from 'repository/services/current-user';
import type ToastService from 'repository/services/toast';
import type { components, paths } from 'schema/openapi';

type Model = components['schemas']['AdminUserDetail'];
type UpdateResponse = paths['/admin/users/{uid}']['patch']['responses']['200']['content']['application/json'];

class AdminUserDetailPage extends Component<{ Args: { model: Model } }> {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare toast: ToastService;

  @tracked notes: string;

  constructor(owner: Owner, args: { model: Model }) {
    super(owner, args);

    this.notes = args.model.notes;
  }

  get isActiveProxy() {
    return this.currentUser.isProxyLoggedInAs(this.args.model.uid);
  }

  @action
  async saveNotes(e: Event) {
    e.preventDefault();

    const { content } = await this.requestManager.request<UpdateResponse>({
      url: `/admin/users/${encodeURIComponent(this.args.model.uid)}`,
      method: 'PATCH',
      data: { user: { notes: this.notes } },
    });

    this.args.model.notes = content.notes;
    this.notes = content.notes;

    this.toast.show('Notes saved.', 'success');
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
            <h3 class="card-title h6">Submission requests ({{@model.submission_requests_count}})</h3>
            <p class="card-text text-body-secondary mb-0">View this user's submission requests.</p>
          </div>
        </LinkTo>
      </div>

      <div class="col-md-6">
        <LinkTo @route="admin.submissions" @query={{hash user=@model.uid}} class="card text-decoration-none h-100">
          <div class="card-body">
            <h3 class="card-title h6">Submissions ({{@model.submissions_count}})</h3>
            <p class="card-text text-body-secondary mb-0">View this user's applied submissions.</p>
          </div>
        </LinkTo>
      </div>
    </div>

    <h2 class="h5 mt-4">Notes</h2>

    <form class="mb-4" {{on "submit" this.saveNotes}}>
      {{#let (uniqueId) as |id|}}
        <label for={{id}} class="visually-hidden">Notes</label>

        <Textarea
          @value={{this.notes}}
          name="notes"
          id={{id}}
          rows="6"
          class="form-control mb-2"
          placeholder="Share context with other administrators (e.g. past correspondence)."
        />

        <button type="submit" class="btn btn-primary">Save</button>
      {{/let}}
    </form>

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
