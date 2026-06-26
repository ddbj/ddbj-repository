import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { array } from '@ember/helper';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';
import Pagination from 'repository/components/pagination';
import StatusBadge from 'repository/components/status-badge';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';

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

      {{#if @model.requests.length}}
        <table class="table border">
          <thead class="table-light">
            <tr>
              <th>ID</th>
              <th>Database</th>
              <th>Status</th>
              <th>Submission</th>
              <th>Created</th>
            </tr>
          </thead>

          <tbody>
            {{#each @model.requests as |request|}}
              <tr>
                <td>
                  <LinkTo @route="request" @models={{array request.db request.id}}>
                    Request-{{request.id}}
                  </LinkTo>
                </td>

                <td>{{dbLabel request.db}}</td>
                <td><StatusBadge @status={{request.status}} @hasAccession={{request.has_accession}} /></td>

                <td>
                  {{#if request.submission_id}}
                    <LinkTo @route="submission" @models={{array request.db request.submission_id}}>
                      Submission-{{request.submission_id}}
                    </LinkTo>
                  {{/if}}
                </td>

                <td>{{formatDatetime request.created_at}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        <Pagination @route="index" @current={{@controller.page}} @total={{@model.totalPages}} />
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
