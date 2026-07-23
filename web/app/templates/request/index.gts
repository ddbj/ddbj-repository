import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { concat } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import StatusBadge from 'repository/components/status-badge';
import ValidityBadge from 'repository/components/validity-badge';
import SubmissionMessages from 'repository/components/submission-messages';
import ReviewerAccess from 'repository/components/reviewer-access';
import autoRefresh from 'repository/modifiers/auto-refresh';
import formatDatetime from 'repository/helpers/format-datetime';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    model: components['schemas']['SubmissionRequest'];
  };
}

export default class extends Component<Signature> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @action
  async apply() {
    const { model } = this.args;

    await this.requestManager.request({
      url: `/submission_requests/${model.id}/submission`,
      method: 'POST',
    });

    await this.router.refresh();
  }

  <template>
    <div {{autoRefresh while=@model.processing interval=1000}}>
      <Breadcrumb @items={{array (hash label="Home" route="index") (hash label=(concat "#" @model.id))}} />

      <h1 class="display-6 mb-4">#{{@model.id}}</h1>

      <dl class="horizontal">
        <dt>Created</dt>
        <dd>{{formatDatetime @model.created_at}}</dd>

        <dt>File</dt>

        <dd>
          <a
            href={{@model.ddbj_record.url}}
            target="_blank"
            rel="noopener noreferrer"
          >{{@model.ddbj_record.filename}}</a>
        </dd>

        <dt>Status</dt>
        <dd><StatusBadge @status={{@model.status}} /></dd>

        {{#if @model.error_message}}
          <dt>Error</dt>
          <dd>{{@model.error_message}}</dd>
        {{/if}}
      </dl>

      {{#if @model.validation}}
        <h2>Validation</h2>

        <dl class="horizontal">
          <dt>Progress</dt>
          <dd class="text-capitalize">{{@model.validation.progress}}</dd>

          <dt>Started</dt>
          <dd>{{formatDatetime @model.validation.created_at}}</dd>

          <dt>Finished</dt>

          <dd>{{formatDatetime @model.validation.finished_at}}</dd>

          <dt>Validity</dt>
          <dd><ValidityBadge @validity={{@model.validation.validity}} /></dd>
        </dl>

        <details class="my-3">
          <summary>Details</summary>

          <table class="table">
            <thead>
              <tr>
                <th>Entry ID</th>
                <th>Code</th>
                <th>Severity</th>
                <th>Message</th>
              </tr>
            </thead>

            <tbody>
              {{#each @model.validation.details as |detail|}}
                <tr>
                  <td>{{detail.entry_id}}</td>
                  <td>{{detail.code}}</td>
                  <td>{{detail.severity}}</td>
                  <td>{{detail.message}}</td>
                </tr>
              {{/each}}
            </tbody>
          </table>
        </details>
      {{/if}}

      {{#if (eq @model.status "ready_to_apply")}}
        <div class="my-3">
          <button type="button" class="btn btn-primary" {{on "click" this.apply}}>
            Apply
          </button>
        </div>
      {{/if}}

      {{#if @model.submission}}
        <h2 class="mt-4">Submission</h2>

        <dl class="horizontal">
          <dt>Source ID</dt>
          <dd>{{or @model.submission.source_id "-"}}</dd>

          <dt>Created</dt>
          <dd>{{formatDatetime @model.submission.created_at}}</dd>

          <dt>Updated</dt>
          <dd>{{formatDatetime @model.submission.updated_at}}</dd>

          <dt>DDBJ Record</dt>

          <dd>
            <a href={{@model.submission.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
              {{@model.submission.ddbj_record.filename}}
            </a>
          </dd>

          <dt>Flatfile (NA)</dt>

          <dd>
            {{#if @model.submission.flatfile_na}}
              <a href={{@model.submission.flatfile_na.url}} target="_blank" rel="noopener noreferrer">
                {{@model.submission.flatfile_na.filename}}
              </a>
            {{else}}
              -
            {{/if}}
          </dd>

          <dt>Flatfile (AA)</dt>

          <dd>
            {{#if @model.submission.flatfile_aa}}
              <a href={{@model.submission.flatfile_aa.url}} target="_blank" rel="noopener noreferrer">
                {{@model.submission.flatfile_aa.filename}}
              </a>
            {{else}}
              -
            {{/if}}
          </dd>

          <dt>Accessions</dt>

          <dd>
            <LinkTo @route="request.accessions" @model={{@model.id}}>{{@model.submission.accessions_count}}</LinkTo>
          </dd>
        </dl>
      {{/if}}

      <SubmissionMessages @requestId={{@model.id}} />

      <ReviewerAccess @requestId={{@model.id}} />
    </div>
  </template>
}
