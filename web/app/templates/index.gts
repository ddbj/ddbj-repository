import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';
import Pagination from 'repository/components/pagination';
import StatusBadge from 'repository/components/status-badge';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import { DB_OPTIONS, STATUS_OPTIONS, isChecked } from 'repository/controllers/index';

import type Controller from 'repository/controllers/index';
import type CurrentUserService from 'repository/services/current-user';
import type { components } from 'schema/openapi';

const authURL = ENV.authURL;

interface Signature {
  Args: {
    model: {
      requests: components['schemas']['SubmissionRequestSummary'][];
      totalPages: number;
    } | null;

    controller: Controller;
  };
}

export default class extends Component<Signature> {
  @service declare currentUser: CurrentUserService;

  <template>
    {{pageTitle "DDBJ Repository"}}

    {{#if this.currentUser.isLoggedIn}}
      <div class="d-flex justify-content-between align-items-center mb-4">
        <h1 class="display-6 mb-0">Submission Requests</h1>
        <LinkTo @route="new" class="btn btn-primary">New Submission</LinkTo>
      </div>

      {{#if (or @model.requests.length @controller.hasActiveFilters)}}
        <form class="card mb-4" {{on "submit" @controller.applyFilters}}>
          <div class="card-body">
            <div class="row mb-2">
              <div class="col-sm-2 fw-semibold">Database</div>
              <div class="col-sm-10">
                {{#each DB_OPTIONS as |opt|}}
                  <div class="form-check form-check-inline">
                    <input
                      type="checkbox"
                      class="form-check-input"
                      id="db-{{opt.value}}"
                      name="db"
                      value={{opt.value}}
                      checked={{isChecked @controller.db opt.value}}
                    />
                    <label class="form-check-label" for="db-{{opt.value}}">{{opt.label}}</label>
                  </div>
                {{/each}}

                <div class="small">
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0 me-3"
                    data-test-select="db"
                    {{on "click" (fn @controller.setFacet "db" true)}}
                  >Select all</button>
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0"
                    data-test-deselect="db"
                    {{on "click" (fn @controller.setFacet "db" false)}}
                  >Deselect all</button>
                </div>
              </div>
            </div>

            <div class="row mb-2">
              <div class="col-sm-2 fw-semibold">Status</div>
              <div class="col-sm-10">
                {{#each STATUS_OPTIONS as |opt|}}
                  <div class="form-check form-check-inline">
                    <input
                      type="checkbox"
                      class="form-check-input"
                      id="status-{{opt.value}}"
                      name="status"
                      value={{opt.value}}
                      checked={{isChecked @controller.status opt.value}}
                    />
                    <label class="form-check-label text-capitalize" for="status-{{opt.value}}">{{opt.label}}</label>
                  </div>
                {{/each}}

                <div class="small">
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0 me-3"
                    data-test-select="status"
                    {{on "click" (fn @controller.setFacet "status" true)}}
                  >Select all</button>
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0"
                    data-test-deselect="status"
                    {{on "click" (fn @controller.setFacet "status" false)}}
                  >Deselect all</button>
                </div>
              </div>
            </div>

            <div class="row mb-2">
              <label for="source-id-filter" class="col-sm-2 col-form-label fw-semibold">Source ID</label>
              <div class="col-sm-10 col-md-5 col-lg-4">
                <input
                  id="source-id-filter"
                  type="search"
                  class="form-control form-control-sm"
                  name="sourceId"
                  placeholder="PSUB / SSUB ..."
                  value={{@controller.sourceId}}
                />
              </div>
            </div>

            <div class="row">
              <div class="col-sm-10 offset-sm-2">
                <button type="submit" class="btn btn-primary btn-sm">Filter</button>
                {{#if @controller.hasActiveFilters}}
                  <button type="button" class="btn btn-link btn-sm" {{on "click" @controller.clearFilters}}>
                    Clear filters
                  </button>
                {{/if}}
              </div>
            </div>
          </div>
        </form>

        {{#if @model.requests.length}}
          <table class="table border">
            <thead class="table-light">
              <tr>
                <th>ID</th>
                <th>Database</th>
                <th>Status</th>
                <th>Accession</th>
                <th>Source ID</th>
                <th>Created</th>
              </tr>
            </thead>

            <tbody>
              {{#each @model.requests as |request|}}
                <tr>
                  <td>
                    <LinkTo @route="request" @model={{request.id}}>
                      #{{request.id}}
                    </LinkTo>

                    {{#if request.has_unread_curator_message}}
                      <span class="badge text-bg-warning ms-2" title="Curator has posted a new message">New message</span>
                    {{/if}}
                  </td>

                  <td>{{dbLabel request.db}}</td>
                  <td><StatusBadge @status={{request.status}} /></td>
                  <td>
                    {{#if request.accession_count}}
                      {{request.first_accession}}
                      {{#unless (eq request.accession_count 1)}}
                        <span class="text-body-secondary ms-1">({{request.accession_count}})</span>
                      {{/unless}}
                    {{else}}
                      -
                    {{/if}}
                  </td>
                  <td>{{or request.source_id "-"}}</td>
                  <td>{{formatDatetime request.created_at}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>

          <Pagination @route="index" @current={{@controller.page}} @total={{@model.totalPages}} />
        {{else}}
          <p class="text-body-secondary">No submission requests match the current filters.</p>
        {{/if}}
      {{else}}
        <p class="text-body-secondary">
          You have no submission requests yet.
          <LinkTo @route="new">Submit a new one</LinkTo>
          to get started.
        </p>
      {{/if}}
    {{else}}
      <div class="row justify-content-center py-5">
        <div class="col-12 col-sm-10 col-md-8 col-lg-6">
          <div class="card shadow-sm">
            <div class="card-body p-4 p-md-5 text-center">
              <h1 class="h3 mb-2">DDBJ Repository</h1>
              <p class="text-body-secondary mb-4">Sign in with your DDBJ Account to continue.</p>

              <form action={{authURL}} method="POST">
                <button type="submit" class="btn btn-primary btn-lg">Login with DDBJ Account</button>
              </form>
            </div>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
